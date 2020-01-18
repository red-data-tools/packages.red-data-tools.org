require "tempfile"
require "thread"

class RepositoryTask
  include Rake::DSL

  class ThreadPool
    def initialize(n_workers=nil, &worker)
      @n_workers = n_workers || detect_n_processors
      @worker = worker
      @jobs = Thread::Queue.new
      @workers = @n_workers.times.collect do
        Thread.new do
          loop do
            job = @jobs.pop
            break if job.nil?
            @worker.call(job)
          end
        end
      end
    end

    def <<(job)
      @jobs << job
    end

    def join
      @n_workers.times do
        @jobs << nil
      end
      @workers.each(&:join)
    end

    private
    def detect_n_processors
      if File.exist?("/proc/cpuinfo")
        File.readlines("/proc/cpuinfo").grep(/^processor/).size
      else
        8
      end
    end
  end

  def define
    define_repository_task
    define_gpg_task
    define_yum_task
    define_apt_task
  end

  private
  def env_value(name)
    value = ENV[name]
    raise "Specify #{name} environment variable" if value.nil?
    value
  end

  def primary_gpg_uid
    gpg_uids.first
  end

  def shorten_gpg_uid(uid)
    uid[-8..-1]
  end

  def gpg_key_path(uid)
    "GPG-KEY-#{shorten_gpg_uid(uid).downcase}"
  end

  def rpm_gpg_key_path(uid)
    "RPM-GPG-KEY-#{shorten_gpg_uid(uid).downcase}"
  end

  def repositories_dir
    "repositories"
  end

  def define_repository_task
    directory repositories_dir
  end

  def define_gpg_task
    gpg_uids.each do |gpg_uid|
      path = gpg_key_path(gpg_uid)
      file path do |task|
        uid = gpg_uid
        unless system("gpg", "--list-keys", uid, :out => IO::NULL)
          sh("gpg",
             "--keyserver", "keyserver.ubuntu.com",
             "--recv-key", uid)
        end
        sh("gpg", "--armor", "--export", uid, :out => path)
      end
    end
  end

  def rpm_version(spec)
    content = File.read(spec)
    version = content.scan(/^Version: (.+)$/)[0][0]
    release = content.scan(/^Release: (.+)$/)[0][0]
    "#{version}-#{release}"
  end

  def signed_rpm?(rpm)
    IO.pipe do |input, output|
      system("rpm", "--checksig", rpm, :out => output)
      signature = input.gets.sub(/\A#{Regexp.escape(rpm)}: /, "")
      signature.split.include?("signatures")
    end
  end

  def detect_unsigned_rpms(directory)
    unsigned_rpms = []
    mutex = Thread::Mutex.new
    thread_pool = ThreadPool.new do |rpm|
      unless signed_rpm?(rpm)
        mutex.synchronize do
          unsigned_rpms << rpm
        end
      end
    end
    Dir.glob("#{directory}/**/*.rpm") do |rpm|
      thread_pool << rpm
    end
    thread_pool.join
    unsigned_rpms
  end

  def define_yum_task
    yum_dir = "yum"
    namespace :yum do
      distribution = "centos"
      rsync_path = rsync_base_path

      desc "Sign packages"
      task :sign => gpg_key_path(primary_gpg_uid) do
        unless system("rpm", "-q", "gpg-pubkey-#{primary_gpg_uid}",
                      :out => IO::NULL)
          sh("rpm", "--import", gpg_key_path(primary_gpg_uid))
        end

        repository_directory = "#{repositories_dir}/#{distribution}"
        unsigned_rpms = detect_unsigned_rpms(repository_directory)
        unless unsigned_rpms.empty?
          sh("rpm",
             "-D", "_gpg_name #{primary_gpg_uid}",
             "-D", "_gpg_digest_algo sha256",
             "-D", "__gpg_check_password_cmd /bin/true true",
             "-D", "__gpg_sign_cmd %{__gpg} gpg --batch --no-verbose --no-armor %{?_gpg_digest_algo:--digest-algo %{_gpg_digest_algo}} --no-secmem-warning -u \"%{_gpg_name}\" -sbo %{__signature_filename} %{__plaintext_filename}",
             "--resign",
             *unsigned_rpms)
        end
      end

      desc "Create symbolic links for Amazon Linux"
      task :amazon_linux do
        cd("#{repositories_dir}/centos") do
          Dir.glob("*") do |path|
            next unless File.directory?(path)
            next unless /\A\d+\z/ =~ path
            next if File.symlink?("#{path}Server")
            ln_s(path, "#{path}Server")
          end
        end
      end

      gpg_key_paths = gpg_uids.collect do |gpg_uid|
        gpg_key_path(gpg_uid)
      end
      desc "Update repositories"
      task :update => gpg_key_paths do
        Dir.glob("#{repositories_dir}/#{distribution}/*") do |version_dir|
          next if File.symlink?(version_dir)
          next unless File.directory?(version_dir)
          Dir.glob("#{version_dir}/*") do |arch_dir|
            next unless File.directory?(arch_dir)
            sh("createrepo",
               "--update",
               arch_dir)
          end
        end
        gpg_uids.each do |gpg_uid|
          cp(gpg_key_path(gpg_uid),
             "#{repositories_dir}/#{distribution}/#{rpm_gpg_key_path(gpg_uid)}")
        end
      end

      desc "Download repositories"
      task :download => repositories_dir do
        sh("rsync",
           "-avz",
           "--progress",
           "--delete",
           "#{rsync_path}/#{distribution}/",
           "#{repositories_dir}/#{distribution}")
      end

      desc "Upload repositories"
      task :upload => repositories_dir do
        sh("rsync",
           "-avz",
           "--progress",
           "--delete",
           "#{repositories_dir}/#{distribution}/",
           "#{rsync_path}/#{distribution}")
      end
    end

    desc "Release Yum packages"
    yum_tasks = [
      "yum:download",
      "yum:sign",
      "yum:amazon_linux",
      "yum:update",
      "yum:upload",
    ]
    task :yum => yum_tasks
  end

  def define_apt_task
    targets = [
      ["debian", "stretch", "main"],
      ["debian", "buster", "main"],
      ["ubuntu", "xenial", "universe"],
      ["ubuntu", "bionic", "universe"],
      ["ubuntu", "eoan", "universe"],
    ]
    distributions = targets.collect(&:first).uniq
    architectures = [
      "i386",
      "amd64",
    ]

    namespace :apt do
      desc "Sign packages"
      task :sign => gpg_key_path(primary_gpg_uid) do
        sh("debsign",
           "--re-sign",
           "-k#{primary_gpg_uid}",
           *Dir.glob("#{repositories_dir}/**/*.{dsc,changes}"))
      end

      namespace :repository do
        desc "Update repositories"
        task :update do
          targets.each do |distribution, code_name, component|
            base_dir = "#{repositories_dir}/#{distribution}"
            pool_dir = "#{base_dir}/pool/#{code_name}"
            next unless File.exist?(pool_dir)
            dists_dir = "#{base_dir}/dists/#{code_name}"
            rm_rf(dists_dir)
            generate_apt_release(dists_dir, code_name, component, "source")
            architectures.each do |architecture|
              generate_apt_release(dists_dir, code_name, component, architecture)
            end

            generate_conf_file = Tempfile.new("apt-ftparchive-generate.conf")
            File.open(generate_conf_file.path, "w") do |conf|
              conf.puts(generate_apt_ftp_archive_generate_conf(code_name,
                                                               component,
                                                               architectures))
            end
            cd(base_dir) do
              sh("apt-ftparchive", "generate", generate_conf_file.path)
            end

            rm_r(Dir.glob("#{dists_dir}/Release*"))
            rm_r(Dir.glob("#{base_dir}/*.db"))
            release_conf_file = Tempfile.new("apt-ftparchive-release.conf")
            File.open(release_conf_file.path, "w") do |conf|
              conf.puts(generate_apt_ftp_archive_release_conf(code_name,
                                                              component,
                                                              architectures))
            end
            release_file = Tempfile.new("apt-ftparchive-release")
            sh("apt-ftparchive",
               "-c", release_conf_file.path,
               "release",
               dists_dir,
               :out => release_file.path)
            release_path = "#{dists_dir}/Release"
            signed_release_path = "#{release_path}.gpg"
            in_release_path = "#{dists_dir}/InRelease"
            mv(release_file.path, release_path)
            chmod(0644, release_path)
            sh("gpg",
               "--sign",
               "--detach-sign",
               "--armor",
               "--local-user", primary_gpg_uid,
               "--output", signed_release_path,
               release_path)
            sh("gpg",
               "--clear-sign",
               "--local-user", primary_gpg_uid,
               "--output", in_release_path,
               release_path)
          end
        end
      end

      desc "Download repositories"
      task :download => repositories_dir do
        distributions.each do |distribution|
          sh("rsync",
             "-avz",
             "--progress",
             "--delete",
             "#{rsync_base_path}/#{distribution}/",
             "#{repositories_dir}/#{distribution}")
        end
      end

      desc "Upload repositories"
      task :upload => [repositories_dir] do
        distributions.each do |distribution|
          sh("rsync",
             "-avz",
             "--progress",
             "--delete",
             "#{repositories_dir}/#{distribution}/",
             "#{rsync_base_path}/#{distribution}")
          keyring_glob = "#{repositories_dir}/#{distribution}"
          keyring_glob << "/pool/*/*/*/*-archive-keyring"
          keyring_glob << "/*-archive-keyring_#{repository_version}-*_all*.deb"
          Dir.glob(keyring_glob) do |path|
            path_components = path.split("/")
            code_name = path_components[-5]
            keyring_deb = "#{path_components[-2]}-latest-#{code_name}.deb"
            sh("scp",
               path,
               "#{rsync_base_path}/#{distribution}/#{keyring_deb}")
          end
        end
      end
    end

    desc "Release APT repositories"
    apt_tasks = [
      "apt:download",
      "apt:sign",
      "apt:repository:update",
      "apt:upload",
    ]
    task :apt => apt_tasks
  end

  def generate_apt_release(dists_dir, code_name, component, architecture)
    dir = "#{dists_dir}/#{component}/"
    if architecture == "source"
      dir << architecture
    else
      dir << "binary-#{architecture}"
    end

    mkdir_p(dir)
    File.open("#{dir}/Release", "w") do |release|
      release.puts(<<-RELEASE)
Archive: #{code_name}
Component: #{component}
Origin: #{repository_label}
Label: #{repository_label}
Architecture: #{architecture}
      RELEASE
    end
  end

  def generate_apt_ftp_archive_generate_conf(code_name, component, architectures)
    conf = <<-CONF
Dir::ArchiveDir ".";
Dir::CacheDir ".";
TreeDefault::Directory "pool/#{code_name}/#{component}";
TreeDefault::SrcDirectory "pool/#{code_name}/#{component}";
Default::Packages::Extensions ".deb";
Default::Packages::Compress ". gzip xz";
Default::Sources::Compress ". gzip xz";
Default::Contents::Compress "gzip";
    CONF

    architectures.each do |architecture|
      conf << <<-CONF

BinDirectory "dists/#{code_name}/#{component}/binary-#{architecture}" {
  Packages "dists/#{code_name}/#{component}/binary-#{architecture}/Packages";
  Contents "dists/#{code_name}/#{component}/Contents-#{architecture}";
  SrcPackages "dists/#{code_name}/#{component}/source/Sources";
};
      CONF
    end

    conf << <<-CONF

Tree "dists/#{code_name}" {
  Sections "#{component}";
  Architectures "#{architectures.join(" ")} source";
};
    CONF

    conf
  end

  def generate_apt_ftp_archive_release_conf(code_name, component, architectures)
    <<-CONF
APT::FTPArchive::Release::Origin "#{repository_label}";
APT::FTPArchive::Release::Label "#{repository_label}";
APT::FTPArchive::Release::Architectures "#{architectures.join(" ")}";
APT::FTPArchive::Release::Codename "#{code_name}";
APT::FTPArchive::Release::Suite "#{code_name}";
APT::FTPArchive::Release::Components "#{component}";
APT::FTPArchive::Release::Description "#{repository_description}";
    CONF
  end
end
