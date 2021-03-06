#!/usr/bin/ruby
require 'json'
require 'digest'
require 'optparse'
require 'open-uri'
require 'pp'

ARCHS = ["x86_64-apple-darwin", "x86_64-pc-linux-gnu", "i686-mingw32", "arm-linux-gnueabihf"]

pkgtemplate = ''
tooltemplatefile = ''
jsonfile = ''
pkg_url= ''
release = ''
repo_url = ''
force = false
pkg_name = 'defaultname'
pkg_maintainer = 'defaultmaintainer'
pkg_website = 'http://example.com'
pkg_email = 'default@example.com'

opt = OptionParser.new
opt.on('-p FILE', '--package-template=FILE') {|o| pkgtemplate = o }
opt.on('-t FILE', '--tool-template=FILE') {|o| tooltemplatefile = o }
opt.on('-j FILE', '--json=FILE') {|o| jsonfile = o }
opt.on('-u PACKAGE_URL', '--url=PACKAGE_URL') {|o| pkg_url= o }
opt.on('-r RELEASE', '--release=RELEASE') {|o| release = o }
opt.on('-g GH_REPO_URL', '--gh-repo=GH_REPO_URL') {|o| repo_url = o }
opt.on('-n PACKAGE_NAME', '--package-name=PACKAGE_NAME') {|o| pkg_name = o }
opt.on('-m PACKAGE_MAINTAINER', '--package-maintainer=PACKAGE_MAINTAINER') {|o| pkg_maintainer = o }
opt.on('-w PACKAGE_WEBSITE', '--package-website=PACKAGE_WEBSITE') {|o| pkg_website = o }
opt.on('-e PACKAGE_EMAIL', '--package-email=PACKAGE_EMAIL') {|o| pkg_email = o }
opt.on('-f', '--force') {|o| force = o }
opt.parse!(ARGV)

STDERR.print("ci_boardmanager.rb ")
ARGV.each {|a| STDERR.print(a); STDERR.print(" ") }
STDERR.print("\n")

slug = repo_url.sub(/https:\/\/github.com\//,'').sub(/\.git$/,'')
user,repo = slug.split('/')
ghpage_url = "https://#{user}.github.io/#{repo}/#{jsonfile}"

suffix = nil
suffix = ".tar.xz" if pkg_url.end_with?(".tar.xz")
suffix = ".tar.bz2" if pkg_url.end_with?(".tar.bz2")
suffix = ".tar.gz" if pkg_url.end_with?(".tar.gz")

raise "invalid archive format #{pkg_url}." if suffix == nil

STDERR.puts("ghpage_url: #{ghpage_url}\n")
STDERR.puts("  repo_url: #{repo_url}\n")
STDERR.puts("   pkg_url: #{pkg_url}\n")

pkgentry = open(pkgtemplate) {|j| JSON.load(j) }
tooltemplate = open(tooltemplatefile) {|j| JSON.load(j) }

bmdata = JSON.load('{ "packages": [ { "platforms": [], "tools": [] }  ] }')
begin
  raise if force
  bmdata = open(ghpage_url) {|f| JSON.load(f) }
rescue => e
  bmdata['packages'][0]['name'] = pkg_name
  bmdata['packages'][0]['maintainer'] = pkg_maintainer
  bmdata['packages'][0]['websiteURL'] = pkg_website
  bmdata['packages'][0]['email'] = pkg_email
  STDERR.puts(e)
  #raise e if not force
end


pkgs = bmdata['packages'][0]["platforms"]

raise if pkgs.find {|x| x["version"] == release} != nil

open(pkg_url) do |ff|
  pkgentry["url"] = pkg_url
  pkgentry["version"] = release.sub(/^.*-/, '')
  pkgentry["archiveFileName"] = repo + '-' + release + suffix
  pkgentry["checksum"] =  "SHA-256:" + Digest::SHA256.hexdigest(ff.read)
  pkgentry["size"] =  "#{ff.size}"
  pkgs.unshift(pkgentry)
end

newtools = tooltemplate.reduce([]) do |entries, tool|
  vers = []
  begin
    vers.push(pkgentry['toolsDependencies'].select {|t| t['name'] == tool['name']}[0]['version'])
  rescue
    vers.push(tool['version']) if tool['version'] != nil
  end

  toolname = tool['name']
  urltemplate = tool['systems'][0]['url']

  tools = vers.collect do |ver|
    syss = ARCHS.collect do |arch|
      url = urltemplate
      url = url.gsub(/\${NAME}/, toolname)
      url = url.gsub(/\${VERSION}/, ver)
      url = url.gsub(/\${ARCH}/, arch)
      begin
        open(url) do |f|
          {
            'archiveFileName' => url.sub(/^.*\//,''),
            'url' => url,
            'host' => arch,
            "checksum" =>  "SHA-256:" + Digest::SHA256.hexdigest(f.read),
            "size" =>  "#{f.size}"
          }
        end
      rescue OpenURI::HTTPError => e
        STDERR.puts("Not found #{url}.")
        nil
      end
    end

    systems = syss.select{|s| s!=nil}
    raise "#{toolname} not found." if systems.length == 0

    {'name'=>toolname, 'version'=>ver, 'systems'=>syss.select{|s| s!=nil} }
  end

  entries.concat(tools)
end

oldvers = bmdata['packages'][0]["tools"].collect {|t| [ t['name'] , t['version'] ] }
newvers = newtools.collect {|t| [ t['name'], t['version'] ] }
toadd = newvers - oldvers

addtools = newtools.select {|t| toadd.include?([t['name'], t['version'] ]) }
addtools.concat( bmdata['packages'][0]["tools"] )
bmdata['packages'][0]["tools"] = addtools

newjson = JSON.pretty_generate(bmdata)
STDOUT.puts(newjson)
