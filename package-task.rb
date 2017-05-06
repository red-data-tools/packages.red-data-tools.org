require "open-uri"

class PackageTask
  include Rake::DSL

  def initialize(package, version)
    @package = package
    @version = version

    @archive_base_name = "#{@package}-#{@version}"
    @archive_name = "#{@archive_base_name}.tar.gz"
    @full_archive_name = File.expand_path(@archive_name)

    @rpm_package = @package

    @rsync_base_path = "packages@packages.groonga.org:public"
    @gpg_uid = "45499429"

    @groonga_source_dir = File.expand_path("#{__dir__}/vendor/groonga")
    @cutter_source_dir = File.expand_path("#{__dir__}/vendor/cutter")
  end

  def define
    define_dist_task
    define_source_task
    define_yum_task
    define_apt_task
    define_ubuntu_task
    define_version_task
  end

  private
  def env_value(name)
    value = ENV[name]
    raise "Specify #{name} environment variable" if value.nil?
    value
  end

  def download(url, download_dir)
    base_name = url.split("/").last
    absolute_output_path = File.join(download_dir, base_name)

    unless File.exist?(absolute_output_path)
      mkdir_p(download_dir)
      rake_output_message "Downloading... #{url}"
      open(url) do |downloaded_file|
        File.open(absolute_output_path, "wb") do |output_file|
          output_file.print(downloaded_file.read)
        end
      end
    end

    absolute_output_path
  end

  def define_dist_task
    define_archive_task
    desc "Create release package"
    task :dist => [@archive_name]
  end

  def define_source_task
    namespace :source do
      rsync_path = "#{@rsync_base_path}/source/#{@package}"
      source_dir = "source"

      desc "Download sources"
      task :download do
        mkdir_p(source_dir)
        sh("rsync",
           "-avz",
           "--progress",
           "--delete",
           "#{rsync_path}/",
           source_dir)
      end

      desc "Upload sources"
      task :upload => [@archive_name] do
        mkdir_p(source_dir)
        cp(@archive_name, source_dir)
        cd(source_dir) do
          ln_sf(@archive_name, "#{@package}-latest.tar.gz")
        end
        sh("rsync",
           "-avz",
           "--progress",
           "--delete",
           "#{source_dir}/",
           rsync_path)
      end
    end

    desc "Release sources"
    source_tasks = [
      "source:download",
      "source:upload",
    ]
    task :source => source_tasks
  end

  def define_yum_task
    namespace :yum do
      distribution = "centos"
      rsync_path = @rsync_base_path
      yum_dir = "yum"
      repositories_dir = "#{yum_dir}/repositories"

      directory repositories_dir

      desc "Build RPM packages"
      task :build => [@archive_name, repositories_dir] do
        tmp_dir = "#{yum_dir}/tmp"
        rm_rf(tmp_dir)
        mkdir_p(tmp_dir)
        cp(@archive_name, tmp_dir)

        env_sh = "#{yum_dir}/env.sh"
        File.open(env_sh, "w") do |file|
          file.puts(<<-ENV)
SOURCE_ARCHIVE=#{@archive_name}
PACKAGE=#{@rpm_package}
VERSION=#{@version}
DEPENDED_PACKAGES="#{rpm_depended_packages.join("\n")}"
          ENV
        end

        tmp_distribution_dir = "#{tmp_dir}/#{distribution}"
        mkdir_p(tmp_distribution_dir)
        spec = "#{tmp_distribution_dir}/#{@rpm_package}.spec"
        spec_in = "#{yum_dir}/#{@rpm_package}.spec.in"
        spec_in_data = File.read(spec_in)
        spec_data = spec_in_data.gsub(/@(.+?)@/) do |matched|
          case $1
          when "PACKAGE"
            @rpm_package
          when "VERSION"
            @version
          else
            matched
          end
        end
        File.open(spec, "w") do |spec_file|
          spec_file.print(spec_data)
        end

        cd(yum_dir) do
          sh("vagrant", "destroy", "--force")
          distribution_versions = {
            "7" => ["x86_64"],
          }
          threads = []
          distribution_versions.each do |ver, archs|
            archs.each do |arch|
              id = "#{distribution}-#{ver}-#{arch}"
              threads << Thread.new(id) do |local_id|
                sh("vagrant", "up", local_id)
                sh("vagrant", "destroy", "--force", local_id)
              end
            end
          end
          threads.each(&:join)
        end
      end

      desc "Sign packages"
      task :sign do
        sh("#{@groonga_source_dir}/packages/yum/sign-rpm.sh",
           @gpg_uid,
           "#{repositories_dir}/",
           distribution)
      end

      desc "Update repositories"
      task :update do
        sh("#{@groonga_source_dir}/packages/yum/update-repository.sh",
           @gpg_uid,
           "groonga",
           "#{repositories_dir}/",
           distribution)
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
      "yum:sign",
      "yum:update",
      "yum:upload",
    ]
    task :yum => yum_tasks
  end

  def define_apt_task
    namespace :apt do
      distribution = "debian"
      code_names = [
        "jessie",
      ]
      architectures = [
        "i386",
        "amd64",
      ]
      rsync_path = @rsync_base_path
      debian_dir = "debian"
      apt_dir = "apt"
      repositories_dir = "#{apt_dir}/repositories"

      directory repositories_dir

      desc "Build DEB packages"
      task :build => [@archive_name, repositories_dir] do
        tmp_dir = "#{apt_dir}/tmp"
        rm_rf(tmp_dir)
        mkdir_p(tmp_dir)
        cp(@archive_name, tmp_dir)
        cp_r(debian_dir, "#{tmp_dir}/debian")

        env_sh = "#{apt_dir}/env.sh"
        File.open(env_sh, "w") do |file|
          file.puts(<<-ENV)
PACKAGE=#{@package}
VERSION=#{@version}
DEPENDED_PACKAGES="#{deb_depended_packages.join("\n")}"
          ENV
        end

        cd(apt_dir) do
          sh("vagrant", "destroy", "--force")
          threads = []
          code_names.each do |code_name|
            architectures.each do |arch|
              id = "#{distribution}-#{code_name}-#{arch}"
              threads << Thread.new(id) do |local_id|
                sh("vagrant", "up", local_id)
                sh("vagrant", "destroy", "--force", local_id)
              end
            end
          end
          threads.each(&:join)
        end
      end

      desc "Sign packages"
      task :sign do
        sh("#{@groonga_source_dir}/packages/apt/sign-packages.sh",
           @gpg_uid,
           "#{repositories_dir}/",
           code_names.join(" "))
      end

      namespace :repository do
        desc "Update repositories"
        task :update do
          sh("#{@groonga_source_dir}/packages/apt/update-repository.sh",
             "Groonga",
             "#{repositories_dir}/",
             architectures.join(" "),
             code_names.join(" "))
        end

        desc "Sign repositories"
        task :sign do
          sh("#{@groonga_source_dir}/packages/apt/sign-repository.sh",
             @gpg_uid,
             "#{repositories_dir}/",
             code_names.join(" "))
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

    desc "Release APT repositories"
    apt_tasks = [
      "apt:download",
      "apt:build",
      "apt:sign",
      "apt:repository:update",
      "apt:repository:sign",
      "apt:upload",
    ]
    task :apt => apt_tasks
  end

  def define_ubuntu_task
    namespace :ubuntu do
      desc "Upload packages"
      task :upload => [@archive_name] do
        ruby("#{@groonga_source_dir}/packages/ubuntu/upload.rb",
             "--package", @package,
             "--version", @version,
             "--source-archive", @archive_name,
             "--code-names", "xenial,yakkety,zesty",
             "--debian-directory", "debian",
             "--pgp-sign-key", env_value("LAUNCHPAD_UPLOADER_PGP_KEY"))
      end
    end

    desc "Release .deb packages for Ubuntu"
    task :ubuntu => ["ubuntu:upload"]
  end

  def define_version_task
    namespace :version do
      desc "Update versions"
      task :update do
        ruby("#{@cutter_source_dir}/misc/update-latest-release.rb",
             @package,
             env_value("OLD_RELEASE"),
             env_value("OLD_RELEASE_DATE"),
             env_value("NEW_RELEASE"),
             env_value("NEW_RELEASE_DATE"),
             "Rakefile",
             "debian/changelog",
             "yum/#{@rpm_package}.spec.in")
      end
    end
  end
end
