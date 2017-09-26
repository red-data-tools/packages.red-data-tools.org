require "tempfile"

class RepositoryTask
  include Rake::DSL

  def initialize
    @rsync_base_path = "packages@packages.red-data-tools.org:public"
    @gpg_uid = "38BA39D6"
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
    namespace :yum do
      distribution = "centos"
      rsync_path = @rsync_base_path
      repositories_dir = "repositories"

      desc "Build release RPM"
      task :build do
        # TODO
      end

      desc "Sign packages"
      task :sign do
        unless system("gpg2", "--list-keys", @gpg_uid, :out => IO::NULL)
          sh("gpg2",
             "--keyserver", "keyserver.ubuntu.com",
             "--recv-key", @gpg_uid)
        end
        unless system("rpm", "-q", "gpg-pubkey-#{@gpg_uid.downcase}",
                      :out => IO::NULL)
          sign_key = Tempfile.new
          sh("gpg2", "--armor", "--export", @gpg_uid, :out => sign_key.path)
          sh("rpm", "--import", sign_key.path)
        end

        unsigned_rpms = []
        Dir.glob("#{repositories_dir}/#{distribution}/**/*.rpm") do |rpm|
          IO.pipe do |input, output|
                 system("rpm", "--checksig", rpm,
               :out => output)
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
      "yum:sign",
      "yum:amazon_linux",
      "yum:update",
      "yum:upload",
    ]
    task :yum => yum_tasks
  end
end
