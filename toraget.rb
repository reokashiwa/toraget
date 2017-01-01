#!/usr/bin/ruby -Ku
# -*- coding: utf-8 -*-

require 'optparse'
require 'uri'
require 'open-uri'
require 'nokogiri'
require 'pstore'
require 'openssl'
require 'tmpdir'

opt = OptionParser.new
OPTS = Hash.new
OPTS[:filename] = nil
OPTS[:indexfile] = "index.db"
opt.on('-c', '--csv-output') {|v| OPTS[:output] = "csv" }
opt.on('-t', '--tsv-output') {|v| OPTS[:output] = "tsv" }
opt.on('-r', '--readable-output') {|v| OPTS[:output] = "readable" }
opt.on('-f', '--filename VAL'){|v| OPTS[:filename] = v}
opt.on('-i VAL', '--indexfile VAL') {|v| OPTS[:indexfile] = v}
opt.parse!(ARGV)

def makeURI(item_id)
  path = "/mailorder/article/" + 
    item_id[0...2] + "/" + item_id[2...6] + "/" + item_id[6...8] + "/" + 
    item_id[8...10] + "/" + item_id[0...12] + ".html"

  URI::Generic.build({:scheme => 'http',
                      :host => 'www.toranoana.jp',
                      :path => path})
end

def getInfo(item_id)
  pageURI = makeURI(item_id)
  doc = Nokogiri::HTML(open(pageURI.to_s, {'Cookie' => 'afg=0'}).read,
                       nil, "CP932")
  detail_main = doc.search('div.detail_main')

  if detail_main[0] == nil
    l = doc.search('td.DetailData_L').children
    r = doc.search('td.DetailData_R').children

    info = {'title' => doc.search('td.td_title_bar_r1c2').children[0].text,
            'circles' =>
            {'name' => doc.search('td.CircleName').children[1].text,
             'URI' => URI::Generic.build(
               {:scheme => 'http',
                :host => 'www.toranoana.jp',
                :path => doc.search('td.CircleName').children[1][:href]})},
            'authors' =>
            {'name' => l[3].text,
             'URI' => URI::Generic.build(
               {:scheme => 'http',
                :host => 'www.toranoana.jp',
                :path => l[3][:href]})},
            'genres' =>
            {'name' => l[6].text,
             'URI' => URI::Generic.build(
               {:scheme => 'http',
                :host => 'www.toranoana.jp',
                :path => l[6][:href]})},
            'characters' => l[8].text, 
            'issue_date' => Date.parse(r[1].text),
            'book_type' => r[0].text,
            'size' => r[2].text.split(' ')[0],
            'page' => r[2].text.split(' ')[1],
            'rating' => 'All ages',
            'comment' => doc.search('td.DetailData_Comment').children[0].text
           }
    if r[3].text =~ /18/
      info['rating'] = 'Ages 18 and up only'
    end
    
  else 
    m = detail_main.children[3].children
    t = detail_main.children[1].children.size - 1

    info = {'title' => detail_main.children[1].children[t].text,
            'circles' => 
            {'name' => m[2].children[0].text,
             'URI' => URI::Generic.build(
               {:scheme => 'http',
                :host => 'www.toranoana.jp',
                :path => m[2].children[0][:href]})},
            'authors' => # Array.new, 
            {'name' => m[5].children[0].text,
             'URI' => URI::Generic.build(
               {:scheme => 'http',
                :host => 'www.toranoana.jp',
                :path => m[5].children[0][:href]})},
            'genres' => # Array.new,
            {'name' => m[8].children[0].text,
             'URI' => URI::Generic.build(
               {:scheme => 'http',
                :host => 'www.toranoana.jp',
                :path => m[8].children[0][:href]})},
            'characters' => m[11].text, 
            'issue_date' => Date.parse(m[14].text),
            'book_type' => m[17].text.split('/')[0].strip,
            'size' => m[17].text.split('/')[1].split(' ')[0],
            'page' => m[17].text.split('/')[1].split(' ')[1],
            'rating' => 'All ages',
            'comment' => detail_main.children[5].children[3].text}

    if m[20].children[0][:alt] =~ /18/
      info['rating'] = 'Ages 18 and up only'
    end
  end

  addDB(item_id, info)

  return info
end

def getImg(doc, item_id)
  dimg = doc.search('div.dimg').children
  i = 0
  while (dimg[i])
    path = "/mailorder/article/" + 
           item_id[0...2] + "/" + item_id[2...6] + "/" + item_id[6...8] + "/" + 
           item_id[8...10] + "/" + dimg[i][:href]

    pageURI = URI::Generic.build({:scheme => 'http',
                                  :host => 'www.toranoana.jp',
                                  :path => path})

    imgdoc = Nokogiri::HTML(open(pageURI.to_s, {'Cookie' => 'afg=0'}).read,
                            nil, "CP932")
    imgURI = URI.parse(imgdoc.search('img').attribute('src').value)

    digest_class = OpenSSL.const_get("OpenSSL::Digest::SHA256")
    digest_object = digest_class.new

    img = open(imgURI.to_s, {'Cookie' => 'afg=0'}){|file|
      buf = ""
      while file.read(16384, buf)
        digest_object.update(buf)
      end
      file.rewind
      open('/tmp/' + digest_object.hexdigest, 'wb'){|imgfile|
        imgfile.write(file.read)
      }
    }
  end
end

def addDB(item_id, info)
  db = PStore.new(OPTS[:indexfile])
  db.transaction do
    if db[item_id] == nil
      db[item_id] = info.dup
    else
      printf("%s\t record exists.\n", item_id)
    end
  end
end

def outputInfo(item_id, info)
  case OPTS[:output]
  when "csv" then
    puts item_id + "," + info['circles']['name'] + "," +
         info['title']
  when "tsv" then
    # Google Spreadsheet では ' で始まる値を文字列とみなす
    puts "'" + item_id + "\t" + info['circles']['name'] + "\t" +
         info['title']
  when "readable" then
    puts info['circles']['name'] + "「" + info['title'] + "」"
  end
end

if File.pipe?(STDIN) then
  STDIN.each{|line|
    item_id = line.chomp
    info = getInfo(item_id)
    outputInfo(item_id, info)
  }

elsif OPTS[:filename] == nil
  item_id = ARGV[0]
  info = getInfo(item_id)
  outputInfo(item_id, info)

elsif
  File.open(OPTS[:filename]) do |file|
    while line = file.gets
      item_id = line.chomp
      info = getInfo(item_id)
      outputInfo(item_id, info)
    end
  end
end
