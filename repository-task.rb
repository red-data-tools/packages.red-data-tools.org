require "tempfile"

class RepositoryTask
  include Rake::DSL

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

  def repository_name
    "red-data-tools"
  end

  def repository_label
    "Red Data Tools"
  end

  def repository_description
    "Red Data Tools related packages"
  end

  def repository_url
    "https://packages.red-data-tools.org"
  end

  def rsync_base_path
    "packages@packages.red-data-tools.org:public"
  end

  def gpg_uid
    "50785E2340D629B2B9823F39807C619DF72898CB"
  end

  def short_gpg_uid
    gpg_uid[-8..-1]
  end

  def gpg_key_path
    "GPG-KEY-#{short_gpg_uid.downcase}"
  end

  def rpm_gpg_key_path
    "RPM-GPG-KEY-#{repository_name}"
  end

  def keyring_path
    "#{repository_name}-keyring.gpg"
  end

  def repositories_dir
    "repositories"
  end

  def deb_keyring_version
    "2017.10.01"
  end

  def expand_variables(text)
    text.gsub(/@(.+?)@/) do |matched|
      case $1
      when "GPG_UID"
        gpg_uid
      else
        matched
      end
    end
  end

  def products
    if ENV["PRODUCTS"]
      ENV["PRODUCTS"].split(",")
    else
      all_products
    end
  end

  def all_products
    [
      "apache-arrow",
      "opencv-glib",
    ]
  end

  def define_repository_task
    directory repositories_dir
  end

  def define_gpg_task
    file gpg_key_path do |task|
      unless system("gpg", "--list-keys", gpg_uid, :out => IO::NULL)
        sh("gpg",
           "--keyserver", "keyserver.ubuntu.com",
           "--recv-key", gpg_uid)
      end
      sh("gpg", "--armor", "--export", gpg_uid, :out => task.name)
    end

    file keyring_path => gpg_key_path do |task|
      rm_f(keyring_path)
      touch(keyring_path)
      sh("gpg",
         "--no-default-keyring",
         "--keyring", "./#{task.name}",
         "--import", gpg_key_path)
    end
  end

  def rpm_version(spec)
    content = File.read(spec)
    version = content.scan(/^Version: (.+)$/)[0][0]
    release = content.scan(/^Release: (.+)$/)[0][0]
    "#{version}-#{release}"
  end

  def define_yum_task
    yum_dir = "yum"
    repo_path = "#{yum_dir}/#{repository_name}.repo"
    release_source_path = "#{yum_dir}/#{repository_name}-release.tar.gz"
    release_spec_path = "#{yum_dir}/#{repository_name}-release.spec"

    file repo_path => __FILE__ do |task|
      File.open(task.name, "w") do |repo|
        repo.puts(<<-REPOSITORY)
[#{repository_name}]
name=#{repository_label} for CentOS $releasever - $basearch
baseurl=#{repository_url}/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/#{rpm_gpg_key_path}
        REPOSITORY
      end
    end

    file release_source_path => [gpg_key_path, repo_path] do |task|
      cp(gpg_key_path, "#{yum_dir}/#{rpm_gpg_key_path}")
      cd(yum_dir) do
        sh("tar", "czf",
           File.basename(task.name),
           rpm_gpg_key_path,
           File.basename(repo_path))
      end
    end

    namespace :yum do
      distribution = "centos"
      rsync_path = rsync_base_path

      namespace :release do
        desc "Build release RPM"
        task :build => [release_source_path, release_spec_path] do
          rpm_dir = "#{Dir.pwd}/rpm"
          rm_rf(rpm_dir)
          mkdir_p(rpm_dir)
          mkdir_p("#{rpm_dir}/SOURCES")
          mkdir_p("#{rpm_dir}/SPECS")
          mkdir_p("#{rpm_dir}/BUILD")
          mkdir_p("#{rpm_dir}/RPMS")
          mkdir_p("#{rpm_dir}/SRPMS")
          cp(release_source_path, "#{rpm_dir}/SOURCES")
          sh("rpmbuild",
             "--define=%_topdir #{rpm_dir}",
             "-ba",
             release_spec_path)
          destination_base_dir = "#{repositories_dir}/#{distribution}/"
          rpms = Dir.glob("#{rpm_dir}/RPMS/**/*.rpm")
          srpms = Dir.glob("#{rpm_dir}/SRPMS/**/*.src.rpm")
          cp(rpms, destination_base_dir)
          cp(srpms, destination_base_dir)
          Dir.glob("#{destination_base_dir}/**/Packages") do |packages_dir|
            cp(rpms, packages_dir)
          end
          Dir.glob("#{destination_base_dir}/**/SPackages") do |srpms_dir|
            cp(srpms, srpms_dir)
          end
          release_rpm_version = rpm_version(release_spec_path)
          release_rpm_base_name = "#{repository_name}-release"
          ln_s("#{release_rpm_base_name}-#{release_rpm_version}.noarch.rpm",
               "#{destination_base_dir}/#{release_rpm_base_name}-latest.noarch.rpm",
               force: true)
          cp(gpg_key_path,
             "#{destination_base_dir}/#{rpm_gpg_key_path}")
        end
      end

      desc "Build RPMs"
      task :build do
        products.each do |product|
          cd(product) do
            ruby("-S", "rake", "yum")
          end
        end
      end

      desc "Copy built RPMs"
      task :copy => repositories_dir do
        products.each do |product|
          sh("rsync", "-av",
             "#{product}/yum/repositories/",
             "#{repositories_dir}/")
        end
      end

      desc "Sign packages"
      task :sign => gpg_key_path do
        unless system("rpm", "-q", "gpg-pubkey-#{gpg_uid}",
                      :out => IO::NULL)
          sh("rpm", "--import", gpg_key_path)
        end

        unsigned_rpms = []
        Dir.glob("#{repositories_dir}/#{distribution}/**/*.rpm") do |rpm|
          IO.pipe do |input, output|
            system("rpm", "--checksig", rpm, :out => output)
            signature = input.gets.sub(/\A#{Regexp.escape(rpm)}: /, "")
            next if /\b(?:gpg|pgp)\b/ =~ signature
            unsigned_rpms << rpm
          end
        end
        unless unsigned_rpms.empty?
          sh("rpm",
             "-D", "_gpg_name #{gpg_uid}",
             "-D", "_gpg_digest_algo sha256",
             "-D", "__gpg /usr/bin/gpg2",
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

      desc "Update repositories"
      task :update => gpg_key_path do
        Dir.glob("#{repositories_dir}/#{distribution}/*") do |version_dir|
          next if File.symlink?(version_dir)
          next unless File.directory?(version_dir)
          Dir.glob("#{version_dir}/*") do |arch_dir|
            next unless File.directory?(arch_dir)
            sh("createrepo", arch_dir)
          end
        end
        cp(gpg_key_path,
           "#{repositories_dir}/#{distribution}/#{rpm_gpg_key_path}")
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
      "yum:build",
      "yum:copy",
      "yum:release:build",
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
      ["ubuntu", "trusty", "universe"],
      ["ubuntu", "xenial", "universe"],
      ["ubuntu", "artful", "universe"],
      ["ubuntu", "bionic", "universe"],
    ]
    distributions = targets.collect(&:first).uniq
    architectures = [
      "i386",
      "amd64",
    ]

    namespace :apt do
      desc "Build .deb"
      task :build do
        products.each do |product|
          cd(product) do
            ruby("-S", "rake", "apt")
          end
        end
      end

      desc "Copy built .deb"
      task :copy => repositories_dir do
        all_products.each do |product|
          distributions.each do |distribution|
            from = "#{product}/apt/repositories/#{distribution}"
            next unless File.exist?(from)
            sh("rsync", "-av", from, "#{repositories_dir}/")
          end
        end
      end

      desc "Sign packages"
      task :sign => gpg_key_path do
        sh("debsign",
           "-pgpg2",
           "--re-sign",
           "-k#{gpg_uid}",
           *Dir.glob("#{repositories_dir}/**/*.{dsc,changes}"))
      end

      namespace :repository do
        desc "Build keyring deb"
        task :build => [repositories_dir, gpg_key_path] do
          tmp_dir = "tmp"
          build_dir = "#{tmp_dir}/build"
          rm_rf(tmp_dir)
          mkdir_p(build_dir)
          cp_r("debian", "#{build_dir}/")
          Dir.glob("#{build_dir}/debian/**/*.in") do |in_path|
            in_content = File.read(in_path)
            out_content = expand_variables(in_content)
            out_path = in_path.gsub(/\.in\z/, "")
            File.open(out_path, "w") do |out|
              out.print(out_content)
            end
            rm(in_path)
          end
          keyring_base_path = "#{repository_name}-keyring"
          keyring_source_path = "#{keyring_base_path}-#{deb_keyring_version}"
          cp(gpg_key_path, "#{build_dir}/#{keyring_base_path}.gpg")
          cd(build_dir) do
            sh("debuild", "--no-tgz-check")
          end
          targets.each do |distribution, code_name, component|
            initial = keyring_base_path[0]
            dir =
              "#{repositories_dir}/#{distribution}/pool/" +
              "#{code_name}/#{component}/#{initial}/#{keyring_base_path}"
            mkdir_p(dir)
            cp(Dir.glob("#{tmp_dir}/*.{deb,tar.*,dsc}"),
               dir)
          end
          rm_rf(tmp_dir)
        end

        desc "Update repositories"
        task :update do
          targets.each do |distribution, code_name, component|
            base_dir = "#{repositories_dir}/#{distribution}"
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
            sh("gpg2",
               "--sign",
               "--detach-sign",
               "--armor",
               "--local-user", gpg_uid,
               "--output", signed_release_path,
               release_path)
            sh("gpg2",
               "--clear-sign",
               "--local-user", gpg_uid,
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
      task :upload => [repositories_dir, keyring_path] do
        distributions.each do |distribution|
          sh("rsync",
             "-avz",
             "--progress",
             "--delete",
             "#{repositories_dir}/#{distribution}/",
             "#{rsync_base_path}/#{distribution}")
          sh("scp", keyring_path, "#{rsync_base_path}/#{distribution}/")
        end
      end
    end

    desc "Release APT repositories"
    apt_tasks = [
      "apt:download",
      "apt:build",
      "apt:copy",
      "apt:sign",
      "apt:repository:build",
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
