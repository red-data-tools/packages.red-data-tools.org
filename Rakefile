# -*- ruby -*-

desc "Update Apache Arrow packages"
task "apache-arrow" do
  cd("apache-arrow") do
    ruby("-S", "rake", "source", "yum", "apt", "ubuntu")
  end
end

desc "Update Apache Arrow GLib packages"
task "apache-arrow-glib" do
  cd("apache-arrow-glib") do
    ruby("-S", "rake", "source", "yum", "apt", "ubuntu")
  end
end

task :default => [
  "apache-arrow",
  "apache-arrow-glib",
]
