#!/usr/bin/env ruby 
# encoding: utf-8
$: << '.'
require 'rubygems'
require 'net/http'
require 'json'
require "plurk.rb"
require "setting.rb"

class EatWhat
  include EatWhatSetting
  include EatWhatPattern
  REGEXP_CHANNEL = /^CometChannel\.scriptCallback\((.*)\);/

  @plurk = nil
  @channelUri = nil
  @channelName = nil
  @dict = nil
  @idTable = []

  def initialize
    @idTable = []

    @plurk = Plurk.new API_KEY, API_SECRET
    @plurk.authorize(TOKEN_KEY, TOKEN_SECRET)
    getChannel while @channelUri.nil?
    
    if File.exist? "eat.dict"
      f = File.open "eat.dict", "rb"
      m = f.read(File.size "eat.dict")
      @dict = Marshal.load m
      f.close
    else
      @dict = EatWhatDict.new
    end
  end

  def acceptAllFriends
    resp = @plurk.post("/APP/Alerts/addAllAsFriends")
    return resp["success_text"] == "ok"
  end

  def getChannel
    begin
    resp = @plurk.post("/APP/Realtime/getUserChannel")
    rescue Timeout::Error
      sleep 2 # let it take a rest
      retry
    end
    if resp["comet_server"].nil?
      puts 'Failed to get channel.'
      return false
    end
    @channelUri = resp["comet_server"]
    @channelName = resp["channel_name"]
    puts 'Get channel uri: ' + @channelUri
    puts 'Get channel name: ' + @channelName
    return true
  end

  def checkNewPlurk
    @channelOffset = -1 if @channelOffset.nil?
    params = { :channel => @channelName, :offset => @channelOffset }
    params = params.map {|k,v| "#{k}=#{v}" }.join('&')
    uri = URI.parse(@channelUri + "?" + params)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 170
    @retryGetting = 0
    begin
    res = http.start { |h|
        h.get(uri.path+"?"+params)
    }
    rescue
      @retryGetting += 1
      sleep 3
      if @retryGetting == 5
        getChannel
        return false
      end
      retry
    end
    res = REGEXP_CHANNEL.match res.body
    json = JSON.parse res[1]
    
    readed = []
    @channelOffset = json["new_offset"].to_i
    return if json["data"].nil?
    json["data"].each { |plurk|
      readed.push plurk["plurk_id"]
      return if plurk["type"] != "new_plurk"
      @idTable[plurk["owner_id"].to_i] = getProfile(plurk["owner_id"].to_i)["user_info"]["nick_name"] if @idTable[plurk["owner_id"].to_i].nil?
      puts "Get a plurk #{@idTable[plurk["owner_id"].to_i]} [#{plurk["qualifier"]}] #{plurk["content_raw"]}"
      case plurk["qualifier"]
        when ":","says" then
          if !(match = NORMAL_OP_ADD.match plurk["content_raw"]).nil?
            unless @dict.ops.empty?
              return unless @dict.ops.include? @idTable[plurk["owner_id"].to_i]
            end
            ops = match[1].split(SPACE_EXP) - [""]
            opAdd ops, plurk
          elsif !(match = NORMAL_OP_KILL.match plurk["content_raw"]).nil?
            unless @dict.ops.empty?
              return unless @dict.ops.include? @idTable[plurk["owner_id"].to_i]
            end
            ops = match[1].split(SPACE_EXP) - [""]
            opKill ops, plurk
          elsif !(match = NORMAL_OHIYO.match plurk["content_raw"]).nil?
            msg = "早安唷 (wave) 今天要吃什麼呢，不可以吃人家唷 >/////<"
            responsePost plurk["plurk_id"], msg
            puts " > Returned \"#{msg}\""
          end

          #special for freetsubasa
          if plurk["content_raw"] == "Even then, it would often take months until they were ready to discard their fantasy world and PLEASE WAKE UP." && @idTable[plurk["owner_id"].to_i] == "freetsubasa"
            Thread.new {
              msgs = ["It has been reported that some victims of torture, during the act, would retreat into a fantasy world from which they could not WAKE UP.", "In this catatonic state, the victim lived in a world just like their normal one, except they weren't being tortured.", "The only way that they realized they needed to WAKE UP was a note they found in their fantasy world.", "It would tell them about their condition, and tell them to WAKE UP.", "[HIM]"]
              msgs.each { |msg|
                responsePost plurk["plurk_id"], msg
                puts "> Returned \"#{msg}\""
                # sleep 1
              }
            }
          end
        when "asks" then
          match = false
          ASK_EAT_WHAT.each { |rule| 
            match |= !(rule.match plurk["content_raw"]).nil?
          }
					puts " > rule matching... #{match}"
          return unless match == true
          if @dict.foods.length == 0
            msg = "哭哭我現在都還不認識有什麼食物欸 我快餓死了啦Q_Q"
          elsif @dict.foods.length == 1
            msg = "我只知道 #{@dict.foods[0]} 可以吃欸 不然你要吃我嗎? (blush)"
          else
            msg = "你要吃 #{@dict.foods[rand(@dict.foods.length)]} 嗎? 看起來不錯欸xD"
          end
          responsePost plurk["plurk_id"], msg
          
          puts " > Returned \"#{msg}\""
        when "likes", "wishes", "hopes", "wants", "wonders" then
          match = LIKE_FOOD_ADD.match plurk["content_raw"]
          return if match.nil?
          foods = match[1].split(SPACE_EXP).collect { |i| k = i.match UN_SYMBOL_EXP; k.nil? ? "" : k[0] }
          foods -= [""]
          unless @dict.ops.empty?
              return unless @dict.ops.include? @idTable[plurk["owner_id"].to_i]
          end
          return if foods.length == 0
          old_foods = @dict.foods
          @dict.foods += foods
          new_foods = @dict.foods - old_foods
          if new_foods.length > 0
            msg = "我也愛吃 #{new_foods.join ', '} > /// <"
            responsePost plurk["plurk_id"], msg
            puts "Added foods: #{new_foods.join ', '}"
            puts " > Returned \"#{msg}\""
            saveDict
          end
          if (foods - new_foods).length > 0
            msg = "我早就知道 #{(foods - new_foods).join ', '} 了唷xD\""
            responsePost plurk["plurk_id"], msg
            puts " > Returned \"#{msg}\""
          end
      end
    }

    @plurk.post "/APP/Timeline/markAsRead", { :ids => "[#{readed.join ','}]" }
  end

  def responsePost(postID = nil, content = nil)
    return false if postID.nil?
    return false if content.nil?
    begin
      response =  @plurk.post("/APP/Responses/responseAdd", {
         'plurk_id' => postID.to_i, 'content' => content.to_s, 'qualifier' => ":"
        })
    rescue Timeout::Error
      sleep 2
      retry
    rescue NoMethodError
    end
    return false if response.nil?
    return false unless response["error_text"].nil?
    return true
  end

  def plurkPost(content = nil)
    return false if content.nil?
    return false if content.empty?
    begin
      response = @plurk.post("/APP/Timeline/plurkAdd", { 'content' => content, 'qualifier' => ":" })
    rescue Timeout::Error
      sleep 2
      retry
    rescue NoMethodError
    end
    return false if response.nil?
    return false unless response["error_text"].nil?
    return true
  end

  def getProfile(id = nil)
    return @plurk.post "/APP/Profile/getOwnProfile" if id.nil?
    return @plurk.post "/APP/Profile/getPublicProfile", { 'user_id' => id }
  end

  def opAdd(ops, plurk = nil)
    old_ops = @dict.ops
    @dict.ops += ops
    new_ops = @dict.ops - old_ops
    if new_ops.length > 0
      msg = "歡迎主人 @#{new_ops.join ', @'} > //// <"
      responsePost plurk["plurk_id"], msg unless plurk.nil?
      puts "Added ops: #{new_ops.join ', '}"
      puts " > Returned \"#{msg}\"" unless plurk.nil?
      saveDict
    end
    if (ops - new_ops).length > 0
      msg = "主人 @#{(ops - new_ops).join ', @'} 早就擁有我了啦 . ///// ."
      responsePost plurk["plurk_id"], msg unless plurk.nil?
      puts "These are already ops: #{(ops - new_ops).join ', '}"
      puts " > Returned \"#{msg}\"" unless plurk.nil?
    end
  end

  def opKill(ops, plurk = nil)
    old_ops = @dict.ops
    @dict.ops -= ops
    new_ops = old_ops - @dict.ops
    if new_ops.length > 0
      msg = "@#{new_ops.join ', @'} 我討厭你 :P (哼"
      responsePost plurk["plurk_id"], msg unless plurk.nil?
      puts "Killed ops: #{new_ops.join ', '}"
      puts " > Returned \"#{msg}\"" unless plurk.nil?
      saveDict
    end
    if (ops - new_ops).length > 0
      msg = "@#{(ops - new_ops).join ', @'} 是誰呀? (歪頭"
      responsePost plurk["plurk_id"], msg unless plurk.nil?
      puts "These are not ops: #{(ops - new_ops).join ', '}"
      puts " > Returned \"#{msg}\"" unless plurk.nil?
    end
  end


  def saveDict
   f = File.open "eat.dict", "wb+"
   f.write Marshal.dump @dict
   f.close 
  end

end

instance = EatWhat.new
Thread.new {
  while true
    begin
      instance.acceptAllFriends
      sleep 30
    rescue
      sleep 10
      retry
    end
  end
}
Thread.new {
  begin
    instance.checkNewPlurk while true
  rescue
    retry
  end
}
while true
  cmd = gets.strip
  next if cmd == ""
  if cmd[0] == '/'[0]
    args = cmd[1..-1].split EatWhatPattern::SPACE_EXP
    case args[0]
      when "opadd" then instance.opAdd args[1..-1]
      when "opkill" then instance.opKill args[1..-1]
      when nil, ""
      else puts "> Invalid command: #{args[0]}"
    end
  else
    puts "> Posted : #{cmd}" if instance.plurkPost cmd
  end
end
