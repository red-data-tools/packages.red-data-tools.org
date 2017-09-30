require "tempfile"

class RepositoryTask
  include Rake::DSL

  def initialize
    @repository_name = "red-data-tools"
    @repository_label = "Red Data Tools"
    @repository_url = "https://packages.red-data-tools.org"
    @rsync_base_path = "packages@packages.red-data-tools.org:public"
    @gpg_uid = "f72898cb"
  end

  def define
    define_yum_task
    # define_apt_task
  end

  private
  def env_value(name)
    value = ENV[name]
    raise "Specify #{name} environment variable" if value.nil?
    value
  end

  def define_yum_task
    yum_dir = "yum"
    gpg_key_path = "#{yum_dir}/RPM-GPG-KEY-#{@repository_name}"
    repo_path = "#{yum_dir}/#{@repository_name}.repo"
    release_source_path = "#{yum_dir}/#{@repository_name}-release.tar.gz"
    release_spec_path = "#{yum_dir}/#{@repository_name}-release.spec"

    file gpg_key_path do |task|
      unless system("gpg2", "--list-keys", @gpg_uid, :out => IO::NULL)
        sh("gpg2",
           "--keyserver", "keyserver.ubuntu.com",
           "--recv-key", @gpg_uid)
      end
      sh("gpg2", "--armor", "--export", @gpg_uid, :out => task.name)
    end

    file repo_path do |task|
      File.open(task.name, "w") do |repo|
        repo.puts(<<-REPOSITORY)
[#{@repository_name}]
name=#{@repository_label} for CentOS $releasever - $basearch
baseurl=#{@repository_url}/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/#{gpg_key_path}
        REPOSITORY
      end
    end

    file release_source_path => [gpg_key_path, repo_path] do |task|
      cd(yum_dir) do
        sh("tar", "czf",
           File.basename(task.name),
           File.basename(gpg_key_path),
           File.basename(repo_path))
      end
    end

    namespace :yum do
      distribution = "centos"
      rsync_path = @rsync_base_path
      repositories_dir = "repositories"

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
          Dir.glob("#{repositories_dir}/#{distribution}/*") do |path|
            next unless File.directory?(path)
            distribution_version_dir = path
            cp(Dir.glob("#{rpm_dir}/SRPMS/**/*.src.rpm"),
               "#{distribution_version_dir}/source/SRPMS/")
            Dir.glob("#{distribution_version_dir}/*/Packages") do |packages_dir|
              cp(Dir.glob("#{rpm_dir}/RPMS/**/*.rpm"),
                 packages_dir)
            end
          end
          cp(gpg_key_path,
             "#{repositories_dir}/#{distribution}/")
        end
      end

      desc "Build RPMs"
      task :build do
        [
          "apache-arrow",
          # "apache-parquet-cpp",
          # "parquet-glib",
        ].each do |repository|
          cd(repository) do
            ruby("-S", "rake", "yum")
            sh("rsync", "-av",
               "#{repository}/yum/repositories/",
               "#{repositories_dir}/centos/")
          end
        end
      end

      desc "Sign packages"
      task :sign => gpg_key_path do
        unless system("rpm", "-q", "gpg-pubkey-#{@gpg_uid}",
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
             "-D", "_gpg_name #{@gpg_uid}",
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
      task :update do
        Dir.glob("#{repositories_dir}/#{distribution}/*/*") do |arch_dir|
          next unless File.directory?(arch_dir)
          sh("createrepo", arch_dir)
        end
        sh("gpg2",
           "--armor",
           "--export",
           @gpg_uid,
           :out => "#{repositories_dir}/#{distribution}/RPM-GPG-KEY-#{@gpg_uid}")
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
      "yum:release:build",
      "yum:sign",
      "yum:amazon_linux",
      "yum:update",
      "yum:upload",
    ]
    task :yum => yum_tasks
  end
end
