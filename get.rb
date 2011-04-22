#!/opt/local/bin/ruby -Ku
# -*- coding: euc-jp -*-

require 'yaml'
require 'optparse'
require 'rubygems'
require 'hpricot'
require 'open-uri'
require 'kconv'
require 'uri'
require 'net/http'

class Net::HTTP
  def initialize_new(address, port = nil)
    initialize_old(address, port)
    @read_timeout = 120
  end
  alias :initialize_old :initialize
  alias :initialize :initialize_new
end

class Fanzine
  def initialize(url)
    @pageURI = url
    @urlarray = Array.new
    @imgurlarray = Array.new
    @title = String.new
  end

  def getImgPageURLs
    titleflag = false
    urlflag = false
    titlelines = Array.new

    retrynum = 0
    while retrynum < 10
      begin
        open(@pageURI.to_s){|f|
          p [f.last_modified, f.status]
          doc = Hpricot(f)
          if /main\.html/ =~ @pageURI.to_s
            @title = (doc/:font).inner_text.toutf8 
            (doc/:a).each{|elem|
              if /page/ =~ elem.inner_text
                subdoc = Hpricot( open(@pageURI.to_s.sub(/[^\/]+\Z/, '') + 
                                       elem["href"] ))
                (subdoc.search('//td[@align="CENTER"]')/:a/:img).each{|elem|
                  @urlarray << URI.parse(@pageURI.to_s.sub(/[^\/]+\Z/, '') + 
                                         elem.parent["href"])
                }
              end
            }
          else 
            @title = (doc/:hr)[ 1 ].next_node.to_s.strip.toutf8
            (doc.search('//td[@align="CENTER"]')/:a/:img).each{|elem|
              @urlarray << URI.parse(@pageURI.to_s + elem.parent["href"])
            }
          end
        }
## old parser (without hpricot)
#         open(@pageURI.to_s) {|f|
#           f.each_line {|line|
#             titleflag = true if /HR width.*color.*red/ =~ line
#             titleflag = false if /<TABLE>/ =~ line
#             urlflag = true if /CENTER.*MIDDLE/ =~ line
#             titlelines << line if titleflag == true
#             if urlflag == true 
#               @urlarray << URI.parse(@pageURI.to_s + line.split(/\"/)[ 9 ])
#               urlflag = false
#             end
#             titleflag = true if /\A<HR width.*>\Z/ =~ line.strip
#           }
#         }
## old parser end
        break
      rescue Timeout::Error
        p "retry"
        retrynum = retrynum + 1
      rescue Errno::ETIMEDOUT
        p "retry"
        retrynum = retrynum + 1
      rescue OpenURI::HTTPError => evar
        p $!.to_s
        retrynum = 10
      end
    end
#     titlelines.each{|line|
#       @title << line.strip.toutf8
#     }
    # @urlarray.each{|url| p url.to_s}
    p @title
  end
  
  def getImgURLs
    if File.exist?(@title)
      p File.ftype(@title) + " " + @title + " exists."
    else
      Dir.mkdir(@title)
    end

    imgflag = false
    @urlarray.each{|url|
      # p url.to_s
      open(url.to_s) {|f|
        f.each_line {|line|
          urlpoint = 1
          imgflag = true if /IMG SRC.*BORDER.*WIDTH.*HEIGHT.*ALT/ =~ line
          urlpoint = 3 if /HREF.*IMG SRC/ =~ line
          if imgflag == true
            # p URI.parse(pageURI.to_s + line.split(/\"/)[ urlpoint ]).to_s
            @imgurlarray << URI.parse(@pageURI.to_s + 
                                     line.split(/\"/)[ urlpoint ])
            imgflag = false
          end
        }
      }
    }
    @imgurlarray.each{|url| p url.to_s}
  end

  def getIMGs
    digitnum = 0
    while true
      if @imgurlarray.size > 10 ** digitnum && 
          @imgurlarray.size <= 10 ** (digitnum + 1)
        break
      end
      digitnum = digitnum + 1
    end
    digitnum = digitnum + 1

    filenum = 0
    filename = String.new
    @imgurlarray.each{|url|
      filename = sprintf("%s/%0#{digitnum}d.jpg", @title, filenum)
      # p url.to_s
      open(filename, 'w') {|out|
        open(url.to_s, "Referer" => url.to_s) {|f|
          out.write(f.read)
        }
      }
      p filename + " has saved."
      filenum = filenum + 1
    }
  end

  def get
    getImgPageURLs
    # getImgURLs
    # getIMGs
  end
end

mode = nil
url = nil
configFileName = 'config.yaml'

OptionParser.new{|opt|
  opt.on('-a') { mode = :all }
  opt.on('-f VAL') {|v| 
    mode = :fanzine
    url = URI.parse(v)
  }
  opt.on('-g VAL') {|v|
    mode = :genre
    url = URI.parse(v)
  }
  opt.on('-c VAL', '--configfile=VAL') {|v| configFileName = v }
}.parse!(ARGV)
p mode

conf = YAML.load_file(configFileName)
url = URI.parse(conf["mainURL"]) if mode == :all && conf["mainURL"] != nil

def getGenreURLs(mainURL)
  genreURLs = Array.new
  doc = Hpricot(open(mainURL.to_s))
  (doc/:td).search('//a[@target="menu"]').each{|elem|
    if elem["href"] =~ URI.regexp
      if /sonota_/ =~ elem["href"]
        subdoc = Hpricot(open(elem["href"]))
        (subdoc/:td).search('//a[@target="_self"]').each{|elem2|
          genreURLs << URI.parse(elem["href"].sub(/[^\/]+\Z/, '') + 
                                 elem2["href"])
        }
      else
        genreURLs << URI.parse(elem["href"])
      end
    end
  }
## old parser (without hpricot)
#   open(mainURL.to_s) {|f|
#     f.each_line {|line|
#       if /target.*menu/ =~ line
#         while line.slice(URI.regexp) != nil
#           sliced = line.slice(URI.regexp)
#           if /sonota_/ =~ sliced
#             open(sliced) {|ff|
#               ff.each_line{|ll|
#                 break if /\A<TR/ =~ ll
#                 genreURLs << sliced.sub(/[^\/]+\Z/, '') + ll.split('"')[ 1 ] if /\A<TD/ =~ ll
#               }
#             }
#           end
#           genreURLs << URI.parse(line.slice!(URI.regexp))
#         end
#       end
#     }
#   }
## old parser end
  genreURLs.uniq! # sonota_ の重複排除
  # genreURLs.each{|url| p url.to_s}
  return genreURLs
end

def getFanzineURLs(genreURL)
  fanzineURLs = Array.new
  doc = Hpricot( open(genreURL.to_s))
  (doc/:td/:a/:img).each{|elem|
    if elem.parent["href"] =~ URI.regexp
      fanzineURLs << URI.parse(elem.parent["href"]) 
    end
  }
## old parser (without hpricot)
#   open(genreURL.to_s) {|gf|
#     gf.each_line{|line|
#       fanzineURLs << URI.parse(line.slice(URI.regexp)) if /TD.*href.*IMG.*\.jpg/ =~ line
#     }
#   }
## old parser end
  return fanzineURLs
end

if mode == :all
  genreURLs = getGenreURLs(url)
  # genreURLs.each{|url| p url.to_s}
  fanzineURLs = Array.new
  genreURLs.each{|gURL|
    array = getFanzineURLs(gURL)
    array.each{|elem| fanzineURLs << elem}
  }
  # fanzineURLs.each{|url| p url.to_s}
  fanzineURLs.each{|fURL|
    fanzine = Fanzine.new(fURL)
    fanzine.get
  }
elsif mode == :genre
  fanzineURLs = getFanzineURLs(url)
  fanzineURLs.each{|fURL|
    fanzine = Fanzine.new(fURL)
    fanzine.get
  }
elsif mode == :fanzine
  fanzine = Fanzine.new(url)
  fanzine.get
end
