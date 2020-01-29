require "tempfile"
require "thread"

class RepositoryTask
  include Rake::DSL

  class ThreadPool
    def initialize(n_workers, &worker)
      @n_workers = n_workers
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
  end

  def define
    define_repository_task
    define_yum_task
    define_apt_task
  end

  private
  def env_value(name)
    value = ENV[name]
    raise "Specify #{name} environment variable" if value.nil?
    value
  end

  def shorten_gpg_key_id(id)
    id[-8..-1]
  end

  def rpm_gpg_key_package_name(id)
    "gpg-pubkey-#{shorten_gpg_key_id(id).downcase}"
  end

  def repositories_dir
    "repositories"
  end

  def define_repository_task
    directory repositories_dir
  end

  def signed_rpm?(rpm)
    IO.pipe do |input, output|
      system("rpm", "--checksig", rpm, :out => output)
      signature = input.gets.sub(/\A#{Regexp.escape(rpm)}: /, "")
      signature.split.include?("signatures")
    end
  end

  def define_yum_task
    yum_dir = "yum"
    namespace :yum do
      distribution = "centos"

      desc "Sign packages"
      task :sign do
        unless system("rpm",
                      "-q", rpm_gpg_key_package_name(repository_gpg_key_id),
                      out: IO::NULL)
          gpg_key = Tempfile.new(["repository", ".asc"])
          sh("gpg",
             "--armor",
             "--export", repository_gpg_key_id,
             out: gpg_key.path)
          sh("rpm", "--import", gpg_key.path)
          gpg_key.close!
        end

        thread_pool = ThreadPool.new(4) do |rpm|
          unless signed_rpm?(rpm)
            sh("rpm",
               "-D", "_gpg_name #{repository_gpg_key_id}",
               "-D", "__gpg_check_password_cmd /bin/true true",
               "--resign",
               *rpm)
          end
        end
        repository_directory = "#{repositories_dir}/#{distribution}"
        Dir.glob("#{repository_directory}/**/*.rpm") do |rpm|
          thread_pool << rpm
        end
        thread_pool.join
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

      desc "Update repositories"
      task :update do
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
      end

      desc "Download repositories"
      task :download => repositories_dir do
        sh("rsync",
           "-avz",
           "--progress",
           "--delete",
           "#{repository_rsync_base_path}/#{distribution}/",
           "#{repositories_dir}/#{distribution}")
      end

      desc "Upload repositories"
      task :upload => repositories_dir do
        sh("rsync",
           "-avz",
           "--progress",
           "--delete",
           "#{repositories_dir}/#{distribution}/",
           "#{repository_rsync_base_path}/#{distribution}")
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

  def apt_targets
    [
      ["debian", "stretch", "main"],
      ["debian", "buster", "main"],
      ["ubuntu", "xenial", "universe"],
      ["ubuntu", "bionic", "universe"],
      ["ubuntu", "eoan", "universe"],
    ]
  end

  def apt_distributions
    apt_targets.collect(&:first).uniq
  end

  def apt_architectures
    [
      "i386",
      "amd64",
    ]
  end

  def define_apt_task
    namespace :apt do
      desc "Download repositories"
      task :download => repositories_dir do
        apt_distributions.each do |distribution|
          sh("rsync",
             "-avz",
             "--progress",
             "--delete",
             "#{repository_rsync_base_path}/#{distribution}/",
             "#{repositories_dir}/#{distribution}")
        end
      end

      desc "Sign packages"
      task :sign do
        Dir.glob("#{repositories_dir}/**/*.{dsc,changes}") do |target|
          begin
            sh({"LANG" => "C"},
               "gpg",
               "--verify",
               target,
               out: IO::NULL,
               err: IO::NULL,
               verbose: false)
          rescue
            sh("debsign",
               "--no-re-sign",
               "-k#{repository_gpg_key_id}",
               target)
          end
        end
      end

      namespace :repository do
        desc "Update repositories"
        task :update do
          apt_targets.each do |distribution, code_name, component|
            base_dir = "#{repositories_dir}/#{distribution}"
            pool_dir = "#{base_dir}/pool/#{code_name}"
            next unless File.exist?(pool_dir)
            dists_dir = "#{base_dir}/dists/#{code_name}"
            rm_rf(dists_dir)
            generate_apt_release(dists_dir, code_name, component, "source")
            apt_architectures.each do |architecture|
              generate_apt_release(dists_dir, code_name, component, architecture)
            end

            generate_conf_file = Tempfile.new("apt-ftparchive-generate.conf")
            File.open(generate_conf_file.path, "w") do |conf|
              conf.puts(generate_apt_ftp_archive_generate_conf(code_name,
                                                               component))
            end
            cd(base_dir) do
              sh("apt-ftparchive", "generate", generate_conf_file.path)
            end

            rm_r(Dir.glob("#{dists_dir}/Release*"))
            rm_r(Dir.glob("#{base_dir}/*.db"))
            release_conf_file = Tempfile.new("apt-ftparchive-release.conf")
            File.open(release_conf_file.path, "w") do |conf|
              conf.puts(generate_apt_ftp_archive_release_conf(code_name,
                                                              component))
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
               "--local-user", repository_gpg_key_id,
               "--output", signed_release_path,
               release_path)
            sh("gpg",
               "--clear-sign",
               "--local-user", repository_gpg_key_id,
               "--output", in_release_path,
               release_path)
          end
        end
      end

      desc "Upload repositories"
      task :upload => [repositories_dir] do
        apt_distributions.each do |distribution|
          sh("rsync",
             "-avz",
             "--progress",
             "--delete",
             "#{repositories_dir}/#{distribution}/",
             "#{repository_rsync_base_path}/#{distribution}")
          keyring_glob = "#{repositories_dir}/#{distribution}"
          keyring_glob << "/pool/*/*/*/*-archive-keyring"
          keyring_glob << "/*-archive-keyring_#{repository_version}-*_all*.deb"
          Dir.glob(keyring_glob) do |path|
            path_components = path.split("/")
            code_name = path_components[-5]
            keyring_deb = "#{path_components[-2]}-latest-#{code_name}.deb"
            sh("scp",
               path,
               "#{repository_rsync_base_path}/#{distribution}/#{keyring_deb}")
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

  def generate_apt_ftp_archive_generate_conf(code_name, component)
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

    apt_architectures.each do |architecture|
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
  Architectures "#{apt_architectures.join(" ")} source";
};
    CONF

    conf
  end

  def generate_apt_ftp_archive_release_conf(code_name, component)
    <<-CONF
APT::FTPArchive::Release::Origin "#{repository_label}";
APT::FTPArchive::Release::Label "#{repository_label}";
APT::FTPArchive::Release::Architectures "#{apt_architectures.join(" ")}";
APT::FTPArchive::Release::Codename "#{code_name}";
APT::FTPArchive::Release::Suite "#{code_name}";
APT::FTPArchive::Release::Components "#{component}";
APT::FTPArchive::Release::Description "#{repository_description}";
    CONF
  end
end
