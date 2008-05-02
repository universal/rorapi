require 'leaves/search_api'
class Rorapi < Autumn::Leaf

#  before_filter :authenticate, :only => [ :reload, :quit ]
 
  def git_command(stem,sender,reply_to,msg)
    reply_to = msg if msg 
    response = "http://github.com/broughcut/rorapi"
    message(response,reply_to)
  end

  def usage_command(stem,sender,reply_to,msg)
    reply_to = msg if msg 
    response = "'?to_json' '?json:fuzzy' '?to_json:all' '?to_json:se' '?to_json:var' '?method:baz:ba' '?method:args nick' '/rorapi ?method:args'"
    message(response,reply_to)
  end

  def q_command(stem,sender,reply_to,msg,detail=false)
    query = msg.split(' ')
    reply_to = query.last.gsub(/#/){} if query.size > 1 
    response = 'not found'
    if query.first =~ /^\?/
      faq = YAML::load(File.read('leaves/api_docs/rails_faq.yml'))
      response = faq.select {|it| it == query.first.gsub(/\W/){}.to_sym}.values.first
    else
      response = search(query.first,detail)
    end
     message(response,reply_to)
  end

  alias Q_command q_command


  private

  def authenticate_filter(stem, channel, sender, command, msg, opts)
    not ([ :operator, :admin, :founder, :channel_owner ] & [ stem.privilege(channel, sender) ].flatten).empty?
  end
end
