# -*- ruby -*-

require "open-uri"

version = "0.2.1.20170319"

package = "apache-arrow"
rsync_base_path = "packages@packages.groonga.org:public"
gpg_uid = "45499429"
groonga_source_dir_candidates = [
  "../groonga.clean",
  "../groonga",
]
groonga_source_dir = groonga_source_dir_candidates.find do |candidate|
  File.exist?(candidate)
end
groonga_source_dir = File.expand_path(groonga_source_dir) if groonga_source_dir
cutter_source_dir = File.expand_path("../cutter")

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

archive_base_name = "#{package}-#{version}"
archive_name = "#{archive_base_name}.tar.gz"

file archive_name do
  full_archive_name = File.expand_path(archive_name)
  cd("../arrow.kou") do
    sh("git", "archive", "HEAD",
       "--prefix", "#{archive_base_name}/",
       "--output", full_archive_name)
  end

  archive_base_name_original = "#{archive_base_name}.original"
  rm_rf(archive_base_name)
  sh("tar", "xf", full_archive_name)
  mv(archive_base_name,
     archive_base_name_original)
  sh("tar", "xf", full_archive_name)
  rm_f(full_archive_name)

  full_arrow_glib_tar_gz = nil
  rm_rf("tmp")
  mkdir_p("tmp/build")
  install_prefix = File.expand_path("tmp/local")
  cd("tmp/build") do
    sh("cmake", "../../#{archive_base_name}/cpp",
       "-DCMAKE_INSTALL_PREFIX=#{install_prefix}",
       "-DARROW_BUILD_TESTS=no")
    sh("make", "-j8")
    sh("make", "install")
  end
  arrow_glib_tar_gz = nil
  cd("#{archive_base_name}/c_glib") do
    sh("./autogen.sh")
    sh("./configure",
       "PKG_CONFIG_PATH=#{install_prefix}/lib/pkgconfig",
       "--enable-gtk-doc",
       "--enable-debug")
    sh({"LD_LIBRARY_PATH" => "#{install_prefix}/lib"},
       "make", "-j8")
    sh("make", "dist")
    arrow_glib_tar_gz = Dir.glob("arrow-glib-*.tar.gz").first
    mv(arrow_glib_tar_gz, "../../")
  end
  rm_rf(archive_base_name)
  mv(archive_base_name_original,
     archive_base_name)
  sh("tar", "xf", arrow_glib_tar_gz)
  rm_rf("#{archive_base_name}/c_glib")
  mv(File.basename(arrow_glib_tar_gz, ".tar.gz"),
     "#{archive_base_name}/c_glib")
  rm_f(arrow_glib_tar_gz)
  sh("tar", "czf", full_archive_name, archive_base_name)
  rm_rf(archive_base_name)
end

desc "Create release package"
task :dist => [archive_name]

packages_dir = "packages"

namespace :package do
  namespace :source do
    rsync_path = "#{rsync_base_path}/source/#{package}"
    source_dir = "#{packages_dir}/source"

    directory source_dir

    desc "Download sources"
    task :download => source_dir do
      sh("rsync", "-avz", "--progress", "--delete", "#{rsync_path}/", source_dir)
    end

    desc "Upload sources"
    task :upload => [archive_name, source_dir] do
      cp(archive_name, source_dir)
      cd(source_dir) do
        ln_sf(archive_name, "#{package}-latest.tar.gz")
      end
      sh("rsync", "-avz", "--progress", "--delete", "#{source_dir}/", rsync_path)
    end
  end

  desc "Release sources"
  source_tasks = [
    "package:source:download",
    "package:source:upload",
  ]
  task :source => source_tasks


  namespace :yum do
    distribution = "centos"
    rsync_path = rsync_base_path
    yum_dir = "#{packages_dir}/yum"
    repositories_dir = "#{yum_dir}/repositories"

    directory repositories_dir

    desc "Build RPM packages"
    task :build => [archive_name, repositories_dir] do
      rpm_package = "arrow"

      tmp_dir = "#{yum_dir}/tmp"
      rm_rf(tmp_dir)
      mkdir_p(tmp_dir)
      cp(archive_name, tmp_dir)

      env_sh = "#{yum_dir}/env.sh"
      File.open(env_sh, "w") do |file|
        file.puts(<<-ENV)
SOURCE_ARCHIVE=#{archive_name}
PACKAGE=#{rpm_package}
VERSION=#{version}
DEPENDED_PACKAGES="
pkg-config
cmake
boost-devel
git
jemalloc-devel
"
        ENV
      end

      tmp_distribution_dir = "#{tmp_dir}/#{distribution}"
      mkdir_p(tmp_distribution_dir)
      spec = "#{tmp_distribution_dir}/#{rpm_package}.spec"
      spec_in = "#{yum_dir}/#{rpm_package}.spec.in"
      spec_in_data = File.read(spec_in)
      spec_data = spec_in_data.gsub(/@(.+)@/) do |matched|
        case $1
        when "PACKAGE"
          rpm_package
        when "VERSION"
          version
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
      sh("#{groonga_source_dir}/packages/yum/sign-rpm.sh",
         gpg_uid,
         "#{repositories_dir}/",
         distribution)
    end

    desc "Update repositories"
    task :update do
      sh("#{groonga_source_dir}/packages/yum/update-repository.sh",
         "groonga",
         "#{repositories_dir}/",
         distribution)
    end

    desc "Download repositories"
    task :download => repositories_dir do
      sh("rsync", "-avz", "--progress",
         "--delete",
         "#{rsync_path}/#{distribution}/",
         "#{repositories_dir}/#{distribution}")
    end

    desc "Upload repositories"
    task :upload => repositories_dir do
      sh("rsync", "-avz", "--progress",
         "--delete",
         "#{repositories_dir}/#{distribution}/",
         "#{rsync_path}/#{distribution}")
    end
  end

  desc "Release Yum packages"
  yum_tasks = [
    "package:yum:download",
    "package:yum:build",
    "package:yum:sign",
    "package:yum:update",
    "package:yum:upload",
  ]
  task :yum => yum_tasks


  namespace :apt do
    distribution = "debian"
    code_names = [
      "jessie",
    ]
    architectures = [
      "i386",
      "amd64",
    ]
    rsync_path = rsync_base_path
    debian_dir = "#{packages_dir}/debian"
    apt_dir = "#{packages_dir}/apt"
    repositories_dir = "#{apt_dir}/repositories"

    directory repositories_dir

    env_sh = "#{apt_dir}/env.sh"
    file env_sh => __FILE__ do
      File.open(env_sh, "w") do |file|
        file.puts(<<-ENV)
PACKAGE=#{package}
VERSION=#{version}
DEPENDED_PACKAGES="
debhelper
pkg-config
cmake
git
libboost-system-dev
libboost-filesystem-dev
libjemalloc-dev
"
        ENV
      end
    end

    desc "Build DEB packages"
    task :build => [archive_name, env_sh, repositories_dir] do
      tmp_dir = "#{apt_dir}/tmp"
      rm_rf(tmp_dir)
      mkdir_p(tmp_dir)
      cp(archive_name, tmp_dir)
      cp_r(debian_dir, "#{tmp_dir}/debian")

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
      sh("#{groonga_source_dir}/packages/apt/sign-packages.sh",
         gpg_uid,
         "#{repositories_dir}/",
         code_names.join(" "))
    end

    namespace :repository do
      desc "Update repositories"
      task :update do
        sh("#{groonga_source_dir}/packages/apt/update-repository.sh",
           "Groonga",
           "#{repositories_dir}/",
           architectures.join(" "),
           code_names.join(" "))
      end

      desc "Sign repositories"
      task :sign do
        sh("#{groonga_source_dir}/packages/apt/sign-repository.sh",
           gpg_uid,
           "#{repositories_dir}/",
           code_names.join(" "))
      end
    end

    desc "Download repositories"
    task :download => repositories_dir do
      sh("rsync", "-avz", "--progress",
         "--delete",
         "#{rsync_path}/#{distribution}/",
         "#{repositories_dir}/#{distribution}")
    end

    desc "Upload repositories"
    task :upload => repositories_dir do
      sh("rsync", "-avz", "--progress",
         "--delete",
         "#{repositories_dir}/#{distribution}/",
         "#{rsync_path}/#{distribution}")
    end
  end

  desc "Release APT packages"
  apt_tasks = [
    "package:apt:download",
    "package:apt:build",
    "package:apt:sign",
    "package:apt:repository:update",
    "package:apt:repository:sign",
    "package:apt:upload",
  ]
  task :apt => apt_tasks


  namespace :ubuntu do
    desc "Upload packages"
    task :upload => [archive_name] do
      ruby("#{groonga_source_dir}/packages/ubuntu/upload.rb",
           "--package", package,
           "--version", version,
           "--source-archive", archive_name,
           "--code-names", "xenial,yakkety",
           "--debian-directory", "packages/debian",
           "--pgp-sign-key", env_value("LAUNCHPAD_UPLOADER_PGP_KEY"))
    end
  end


  namespace :version do
    desc "Update versions"
    task :update do
      ruby("#{cutter_source_dir}/misc/update-latest-release.rb",
           package,
           env_value("OLD_RELEASE"),
           env_value("OLD_RELEASE_DATE"),
           version,
           env_value("NEW_RELEASE_DATE"),
           "README.md",
           "packages/debian/changelog",
           "packages/yum/#{package}.spec.in")
    end
  end
end
