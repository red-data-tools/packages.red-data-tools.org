require "pathname"
require "tempfile"
require "thread"

require "apt-dists-merge"

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
    gpg_key_id = shorten_gpg_key_id(repository_gpg_key_id).downcase
    IO.pipe do |input, output|
      result = ""
      read_thread = Thread.new do
        input.each_line do |line|
          result << line
        end
      end
      system("rpm", "--checksig", "--verbose", rpm, out: output)
      output.close
      read_thread.join
      result.include?("key ID #{gpg_key_id}: OK")
    end
  end

  def yum_targets
    [
      ["almalinux", "9"],
      ["almalinux", "8"],
      ["centos", "7"],
    ]
  end

  def yum_distributions
    yum_targets.collect(&:first).uniq
  end

  def define_yum_task
    yum_dir = "yum"
    namespace :yum do
      namespace :base do
        desc "Download base repodata"
        task :download => repositories_dir do
          yum_distributions.each do |distribution|
            dir = "#{repositories_dir}/base/#{distribution}"

            # Ensure directory on server.
            empty_dir = "#{dir}.empty"
            rm_rf(empty_dir)
            mkdir_p(empty_dir)
            sh("rsync",
               "-av",
               "#{empty_dir}/",
               "#{repository_rsync_base_path}/#{distribution}/")

            sh("rsync",
               "-avz",
               "--progress",
               "--delete",
               "--include=*/",
               "--include=*/*/",
               "--include=*/*/repodata/",
               "--include=*/*/repodata/*",
               "--include=*/*/repodata/*/*",
               "--exclude=*",
               "#{repository_rsync_base_path}/#{distribution}/",
               dir)
          end
        end
      end

      namespace :incoming do
        desc "Download incoming packages"
        task :download => repositories_dir do
          command_line = [
            "rsync",
            "-avz",
            "--progress",
            "--delete",
            "--delete-excluded",
          ]
          yum_distributions.each do |distribution|
            command_line << "--include=#{distribution}/"
            command_line << "--include=#{distribution}/*"
            command_line << "--include=#{distribution}/**/*"
          end
          command_line << "--exclude=*"
          command_line << "#{repository_rsync_base_path}/incoming/"
          command_line << "#{repositories_dir}/incoming"
          sh(*command_line)
        end

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
          yum_targets.each do |distribution, version|
            repository_directory =
              "#{repositories_dir}/incoming/#{distribution}/#{version}"
            Dir.glob("#{repository_directory}/**/*.rpm") do |rpm|
              thread_pool << rpm
            end
          end
          thread_pool.join
        end
      end

      desc "Update repositories"
      task :update do
        yum_targets.each do |distribution, version|
          base_version_dir =
            File.expand_path("#{repositories_dir}/base/#{distribution}/#{version}")
          incoming_version_dir =
            "#{repositories_dir}/incoming/#{distribution}/#{version}"
          next unless File.directory?(incoming_version_dir)
          Dir.glob("#{incoming_version_dir}/*") do |incoming_arch_dir|
            next unless File.directory?(incoming_arch_dir)
            base_arch_dir =
              "#{base_version_dir}/#{File.basename(incoming_arch_dir)}"
            rm_rf("#{incoming_arch_dir}/repodata")
            base_repodata_dir = "#{base_arch_dir}/repodata"
            if File.exist?(base_repodata_dir)
              cp_r(base_repodata_dir,
                   incoming_arch_dir,
                   preserve: true)
            end
            packages = Tempfile.new("createrepo-c-packages")
            Pathname.glob("#{incoming_arch_dir}/*/*.rpm") do |rpm|
              relative_rpm = rpm.relative_path_from(incoming_arch_dir)
              packages.puts(relative_rpm.to_s)
            end
            packages.close
            sh("createrepo_c",
               "--pkglist", packages.path,
               "--recycle-pkglist",
               "--retain-old-md-by-age=0",
               "--skip-stat",
               "--update",
               incoming_arch_dir)
          end
        end
      end

      desc "Upload repositories"
      task :upload => repositories_dir do
        yum_distributions.each do |distribution|
          sh("rsync",
             "-avz",
             "--progress",
             "--exclude=*/*/repodata/",
             "#{repositories_dir}/incoming/#{distribution}/",
             "#{repository_rsync_base_path}/#{distribution}/")
        end

        yum_targets.each do |distribution, version|
          incoming_version_dir =
            "#{repositories_dir}/incoming/#{distribution}/#{version}"
          next unless File.directory?(incoming_version_dir)
          Dir.glob("#{incoming_version_dir}/*") do |incoming_arch_dir|
            next unless File.directory?(incoming_arch_dir)
            arch = File.basename(incoming_arch_dir)
            sh("rsync",
               "-avz",
               "--progress",
               "--delete",
               "#{incoming_arch_dir}/repodata",
               "#{repository_rsync_base_path}/#{distribution}/#{version}/#{arch}")
          end
        end
      end

      namespace :incoming do
        desc "Remove incoming packages"
        task :remove => [repositories_dir] do
          yum_distributions.each do |distribution|
            dir = "#{repositories_dir}/incoming/#{distribution}"
            rm_rf(dir)
            mkdir_p(dir)
            sh("rsync",
               "-avz",
               "--progress",
               "--delete",
               "#{dir}/",
               "#{repository_rsync_base_path}/incoming/#{distribution}/")
          end
        end
      end

      namespace :recovery do
        recovery_dir = "#{repositories_dir}/recovery"

        desc "Download repositories"
        task :download => repositories_dir do
          yum_targets.each do |distribution, version|
            relative_path = "#{distribution}/#{version}"
            destination_dir = "#{recovery_dir}/#{relative_path}"
            mkdir_p(destination_dir)
            sh("rsync",
               "-avz",
               "--progress",
               "--delete",
               "#{repository_rsync_base_path}/#{relative_path}/",
               destination_dir)
          end
        end

        namespace :repository do
          desc "Update repositories with full packages"
          task :update do
            yum_targets.each do |distribution, version|
              version_dir = "#{recovery_dir}/#{distribution}/#{version}"
              next if File.symlink?(version_dir)
              next unless File.directory?(version_dir)
              Dir.glob("#{version_dir}/*") do |arch_dir|
                next unless File.directory?(arch_dir)
                sh("createrepo_c",
                   "--update",
                   arch_dir)
              end
            end
          end
        end

        desc "Upload repositories"
        task :upload => repositories_dir do
          yum_targets.each do |distribution, version|
            version_dir = "#{recovery_dir}/#{distribution}/#{version}"
            next if File.symlink?(version_dir)
            next unless File.directory?(version_dir)
            Dir.glob("#{version_dir}/*/repodata") do |repodata_dir|
              arch_dir = File.dirname(repodata_dir)
              destination = [
                repository_rsync_base_path,
                distribution,
                version,
                File.basename(arch_dir),
                File.basename(repodata_dir),
              ].join("/")
              sh("rsync",
                 "-avz",
                 "--progress",
                 "--delete",
                 "#{repodata_dir}/",
                 destination)
            end
          end
        end
      end

      desc "Recover Yum repositories"
      recover_tasks = [
        "yum:recovery:download",
        "yum:recovery:repository:update",
        "yum:recovery:upload",
      ]
      task :recover => recover_tasks
    end

    desc "Release Yum packages"
    yum_tasks = [
      "yum:base:download",
      "yum:incoming:download",
      "yum:incoming:sign",
      "yum:update",
      "yum:upload",
      "yum:incoming:remove",
    ]
    task :yum => yum_tasks
  end

  def apt_targets_default
    [
      ["debian", "bullseye", "main"],
      ["debian", "bookworm", "main"],
      ["ubuntu", "focal", "universe"],
      ["ubuntu", "jammy", "universe"],
      ["ubuntu", "lunar", "universe"],
    ]
  end

  def apt_targets
    targets = (ENV["APT_TARGETS"] || "").split(",")
    return apt_targets_default if targets.empty?

    targets.collect do |target|
      target.split("-")
    end
  end

  def apt_distributions
    apt_targets.collect(&:first).uniq
  end

  def apt_architectures
    [
      "amd64",
      "arm64",
      "i386",
    ]
  end

  def define_apt_task
    namespace :apt do
      namespace :base do
        desc "Download base dists"
        task :download => repositories_dir do
          apt_distributions.each do |distribution|
            base_dists_dir = "#{repositories_dir}/base/#{distribution}/dists"
            mkdir_p(base_dists_dir)
            sh("rsync",
               "-avz",
               "--progress",
               "--delete",
               "#{repository_rsync_base_path}/#{distribution}/dists/",
               base_dists_dir)
          end
        end
      end

      namespace :incoming do
        desc "Download incoming packages"
        task :download => repositories_dir do
          command_line = [
            "rsync",
            "-avz",
            "--progress",
            "--delete",
            "--delete-excluded",
          ]
          apt_distributions.each do |distribution|
            command_line << "--include=#{distribution}/"
            command_line << "--include=#{distribution}/*.*"
            command_line << "--include=#{distribution}/pool/"
            command_line << "--include=#{distribution}/pool/*"
            command_line << "--include=#{distribution}/pool/**/*"
          end
          command_line << "--exclude=*"
          command_line << "#{repository_rsync_base_path}/incoming/"
          command_line << "#{repositories_dir}/incoming"
          sh(*command_line)
        end

        desc "Sign packages"
        task :sign do
          Dir.glob("#{repositories_dir}/incoming/**/*.{dsc,changes}") do |target|
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
      end

      namespace :repository do
        desc "Update repositories"
        task :update do
          apt_targets.each do |distribution, code_name, component|
            base_dir = "#{repositories_dir}/incoming/#{distribution}"
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
            mv(release_file.path, "#{dists_dir}/Release")

            base_dists_dir =
              "#{repositories_dir}/base/#{distribution}/dists/#{code_name}"
            merged_dists_dir =
              "#{repositories_dir}/merged/#{distribution}/dists/#{code_name}"
            rm_rf(merged_dists_dir)
            merger = APTDistsMerge::Merger.new(base_dists_dir,
                                               dists_dir,
                                               merged_dists_dir)
            merger.merge

            in_release_path = "#{merged_dists_dir}/InRelease"
            release_path = "#{merged_dists_dir}/Release"
            signed_release_path = "#{release_path}.gpg"
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
          distribution_dir = "#{repositories_dir}/incoming/#{distribution}/"
          if File.exist?(distribution_dir)
            sh("rsync",
               "-avz",
               "--progress",
               "--exclude=dists/",
               distribution_dir,
               "#{repository_rsync_base_path}/#{distribution}")
          end
          dists_dir = "#{repositories_dir}/merged/#{distribution}/dists/"
          if File.exist?(dists_dir)
            command_line = [
              "rsync",
              "-avz",
              "--progress",
              "--delete",
            ]
            Dir.glob("#{dists_dir}/*") do |dists_code_name_dir|
              code_name = File.basename(dists_code_name_dir)
              command_line << "--include=#{code_name}/"
              command_line << "--include=#{code_name}/*"
              command_line << "--include=#{code_name}/**/*"
            end
            command_line << "--exclude=*"
            command_line << dists_dir
            command_line << "#{repository_rsync_base_path}/#{distribution}/dists"
            sh(*command_line)
          end
        end
      end

      namespace :incoming do
        desc "Remove incoming packages"
        task :remove => [repositories_dir] do
          apt_distributions.each do |distribution|
            dir = "#{repositories_dir}/incoming/#{distribution}"
            rm_rf(dir)
            mkdir_p(dir)
            sh("rsync",
               "-avz",
               "--progress",
               "--delete",
               "#{dir}/",
               "#{repository_rsync_base_path}/incoming/#{distribution}/")
          end
        end
      end

      namespace :recovery do
        recovery_dir = "#{repositories_dir}/recovery"

        desc "Download repositories"
        task :download => repositories_dir do
          apt_targets.each do |distribution, code_name, component|
            relative_path = "#{distribution}/pool/#{code_name}"
            destination_dir = "#{recovery_dir}/#{relative_path}"
            mkdir_p(destination_dir)
            sh("rsync",
               "-avz",
               "--progress",
               "--delete",
               "#{repository_rsync_base_path}/#{relative_path}/",
               destination_dir)
          end
        end

        namespace :repository do
          desc "Update repositories with full packages"
          task :update do
            apt_targets.each do |distribution, code_name, component|
              base_dir = "#{recovery_dir}/#{distribution}"
              dists_dir = "#{base_dir}/dists/#{code_name}"
              rm_rf(dists_dir)
              generate_apt_release(dists_dir, code_name, component, "source")
              apt_architectures.each do |architecture|
                generate_apt_release(dists_dir,
                                     code_name,
                                     component,
                                     architecture)
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
              release_path = "#{dists_dir}/Release"
              sh("apt-ftparchive",
                 "-c", release_conf_file.path,
                 "release",
                 dists_dir,
                 :out => release_file.path)
              mv(release_file.path, "#{dists_dir}/Release")
              signed_release_path = "#{release_path}.gpg"
              sh("gpg",
                 "--sign",
                 "--detach-sign",
                 "--armor",
                 "--local-user", repository_gpg_key_id,
                 "--output", signed_release_path,
                 release_path)
              in_release_path = "#{dists_dir}/InRelease"
              sh("gpg",
                 "--clear-sign",
                 "--local-user", repository_gpg_key_id,
                 "--output", in_release_path,
                 release_path)
            end
          end
        end

        desc "Upload repositories"
        task :upload do
          apt_targets.each do |distribution, code_name, component|
            relative_dir = "#{distribution}/dists/#{code_name}"
            sh("rsync",
               "-avz",
               "--progress",
               "--delete",
               "#{recovery_dir}/#{relative_dir}/",
               "#{repository_rsync_base_path}/#{relative_dir}")
          end
        end
      end

      desc "Recover APT repositories"
      recover_tasks = [
        "apt:recovery:download",
        "apt:recovery:repository:update",
        "apt:recovery:upload",
      ]
      task :recover => recover_tasks
    end

    desc "Release APT repositories"
    apt_tasks = [
      "apt:base:download",
      "apt:incoming:download",
      "apt:incoming:sign",
      "apt:repository:update",
      "apt:upload",
      "apt:incoming:remove",
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
