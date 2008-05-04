#require 'rubygems'
#require 'hpricot'
#require 'yaml'
require 'net/http'
require 'hpricot'
require 'leaves/search_api'

class Rorapi < Autumn::Leaf

#  before_filter :authenticate, :only => [ :reload, :quit ]

  def git_command(stem,sender,reply_to,msg)
    message(poll_edge,reply_to)
  end


  def wire_command(stem,sender,reply_to,msg)
    unless @polling
      @polling = true
      go_wire
    end
  end


  def usage_command(stem,sender,reply_to,msg)
    reply_to = msg if msg 
    response = "usage: http://gotchunk.blogspot.com/2008/05/rorbby-rubyonrails-api-bot.html"
    message(response,reply_to)
  end

  def define_command(stem,sender,reply_to,define,msg)
    faq = YAML::load(File.read('leaves/api_docs/rails_faq.yml'))
    definition = msg.gsub(/\*$|<<|>>|\s{2,}/){}.strip
    definition_set = definition.split(',')
    definition_set.map! {|it| it.strip}
    if msg =~ /^<</
      faq[define] ||= []
      if faq[define].is_a?(Array)
        faq[define] << definition_set
        faq[define].flatten!
        faq[define].uniq!
      end
    elsif faq[define] && msg =~ /^>>/
      faq[define].delete(definition)
    elsif faq[define] && msg =~ /\*$/ || !faq[define]
      faq[define] = definition
    end
    File.open("leaves/api_docs/rails_faq.yml","w+") {|f| f.puts faq.to_yaml}
  end

  def q_command(stem,sender,reply_to,msg,detail=false)
    query = msg.split(' ')
    reply_to = query[1].gsub(/#/){} if query.size > 1 
    detail = true if query.size > 1
    if query.first =~ /^\?/
      faq = YAML::load(File.read('leaves/api_docs/rails_faq.yml'))
      item = faq.select {|it| it == query.first.gsub(/\W/){}.to_sym}.values.first
      response = item
      response = item.join(', ') if item.is_a?(Array)
    else
      response = search(query.first,detail)
    end
     message(response,reply_to)
  end

  alias Q_command q_command

  def rails_edge
    file = File.read("leaves/wire/rails/commits.yml")
    commits = YAML::load(file)
    response = Net::HTTP.get("github.com","/feeds/rails/commits/rails/master")
    xml = Hpricot.XML(response.body)
    commit = {}
    commit[:title] = xml.at(:entry).at(:title).inner_text
    commit[:date] = xml.at(:entry).at(:updated).inner_text
    File.open("leaves/wire/rails/commits.yml","w+") {|f| f.puts commit.to_yaml}
    if commits && !commits.eql?(commit)
      msg = "New edge commit: #{commit[:title]} #{Date.parse(commit[:date]).strftime("%I%p %e/%m")}"
      message(msg,"#rorbot")
      message(msg,"#rubyonrails")
      message(msg,"#rails-contrib")
    end
  end

  def rails_tix
    old = YAML::load(File.open("leaves/wire/rails/tix_archive.yml")) 
    tix = YAML::load(File.open("leaves/wire/rails/tix.yml"))
    tix ||= []
    old ||= []
    old << tix
    new_tix = poll_lighthouse
    if !tix.eql?(new_tix)
      ticket = new_tix.first
      prev_version = old.flatten.select {|it| it[:uri] == ticket[:uri]}.first
      return if prev_version && prev_version[:state] == ticket[:state]
      case ticket[:state].to_sym
      when :invalid, :resolved, :incomplete, :open
        about = "Ticket #{ticket[:num]} is #{ticket[:state]}"
      when :new
        about = "New ticket (#{ticket[:num]})"
      end
      p msg = "Lighthouse: #{about}: #{ticket[:title]} #{ticket[:assigned]} #{ticket[:uri]}"
      message(msg,"#rorbot")
      message(msg,"#rubyonrails")
      message(msg,"#rails-contrib")
    end
  end

  def poll_lighthouse
    server = "rails.lighthouseapp.com"
    page = "/projects/8994-ruby-on-rails/tickets"
    doc = get(server,page)
    tickets = []
    #count = doc.at(".pagination").search(:a)[-2].inner_text.to_i
    count = 1
    count.times do |i|
      doc = get(server,"#{page}?page=#{i+1}")
      (doc/"#open-tickets tr").each do |ticket|
        t = {}
        link = ticket.search(:a)[1]
        t[:state] = ticket.at(".tstate").inner_text.split.last
        t[:num] = ticket.at(".tnum").inner_text.to_i
        t[:title] = link.inner_text
        assignee = ticket.search(:td)[3].inner_text.gsub(/\?/){}
        t[:assigned] = nil
        t[:assigned] = "Assigned: #{assignee}" unless assignee.empty?
        t[:uri] = "http://rails.lighthouseapp.com#{link[:href]}"
        t[:uri] = tinyuri(t[:uri]) if count == 1
        tickets << t
      end
    end
    count > 1 ? title = 'tix_archive' : title = 'tix'
    File.open("leaves/wire/rails/#{title}.yml","w+") {|f| f.puts tickets.to_yaml}
    tickets
  end

  private

  def go_wire
    while @polling
      rails_tix
      rails_edge
      sleep 300
    end
  end


  def get(server,page) #will class this out to eventmachine client
    response = Net::HTTP.get(server,page)
    Hpricot(response)
  end

  def tinyuri(uri)
    file = File.read("leaves/wire/rails/tinyuris.yml")
    tix = YAML::load(file)
    tix ||= {}
    unless tix[uri]
      doc = get("tinyurl.com","/create.php?url=#{uri}")
      tix[uri] = (doc/:blockquote)[1].at(:b).inner_text
      File.open("leaves/wire/rails/tinyuris.yml","w+") {|f| f.puts tix.to_yaml}
    end
    tix[uri]
  end

  def authenticate_filter(stem, channel, sender, command, msg, opts)
    not ([ :operator, :admin, :founder, :channel_owner ] & [ stem.privilege(channel, sender) ].flatten).empty?
  end
end
