#TODO use initializers
#TODO transmission settings on file

require 'open-uri'
require 'mechanize'
require 'pp'
require 'pry'
# require 'java'
#
# $CLASSPATH << File.expand_path('../../../target/classes', File.dirname(__FILE__))
#
# java_import com.fernandodoming.fetch.models.Episode
# java_import com.fernandodoming.fetch.models.Season
# java_import com.fernandodoming.fetch.models.Show
require_relative 'lib/showtime'
require_relative 'lib/kat'

client = Showtime::Client.instance
client.subscriptions.each do |subscription|
  client.shows << Showtime::Show.new(subscription['link'])
end

changes = client.pull
client.download_new changes
client.save changes

##########
__END__

agent = Mechanize.new

# Load subscriptions YML
config_path = File.expand_path('../../../config/', File.dirname(__FILE__))
subscriptions = Psych.load_file config_path + '/subscriptions.yml'
Trans::Api::Client.config = { host: '192.168.1.10', port: 9091, path: '/transmission/rpc' }

shows = []
subscriptions['subscriptions'].each do |subscription|

  # Fetch and parse HTML document
  page = agent.get subscription['link']
  show_title = page.search('table.doublecelltable h1').first.text

  show = { 'title' => show_title, 'link' => subscription['link'], 'seasons' => [] }
  #show = Show.new show_title, subscription['link']

  # Seasons
  page.search('table.doublecelltable br + h3').reverse_each do |season_header|

    pp 'Season: ' + season_header.text
    #season = Season.new season_header.text
    season = { 'title' => season_header.text, 'episodes' => [] }
    show['seasons'] << season

    # Episodes
    season_header.next_element.search('div.infoList div.infoListCut').reverse_each do |episode_link|

      # Get episodes ids
      id = episode_link.attribute 'onclick'
      id = id.text.scan(/\d+/).first

      # Check if episodes are already downloaded
      #shows = Psych.load_file config_path + '/shows.yml'

      # Get torrents page for an episode
      torrents_page = agent.get 'http://kat.cr/media/getepisode/' + id + '/'
      pp 'http://kat.cr/media/getepisode/' + id + '/'

      # Get page links for torrents
      (torrents = torrents_page.search('a.cellMainLink')).each do |torrent|
        pp torrent.text
      end

      unless torrents.empty?
        # torrent = Criteria.best torrents
        torrent = torrents.first
        #episode = Episode.new torrent.text, id, 'http://kat.cr' + torrent.attribute('href').text
        episode = {
            'title' => torrent.text,
            'id' => id,
            'link' => 'http://kat.cr' + torrent.attribute('href').text,
            'downloaded' => false
        }
        season['episodes'] << episode
      end
    end
  end
  shows << show
end

local_shows = Psych.load_file config_path + '/shows.yml'
local_shows = [] if local_shows.nil? || local_shows == false

unless local_shows == shows   # if there are changes
  shows.each_with_index do |show, show_index|
    local_shows[show_index] = show if local_shows[show_index].nil?    # A new show has been added
    local_show = local_shows[show_index]

    show['seasons'].each_with_index do |season, season_index|
      local_show['seasons'] = [] if local_show['seasons'].nil?
      local_season = local_show['seasons'][season_index] = season if local_show['seasons'][season_index].nil?   # A new season has been added

      season['episodes'].each_with_index do |episode, episode_index|
        local_show['seasons'][season_index]['episodes'] = [] if local_show['seasons'][season_index]['episodes'].nil?
        local_episode = local_show['seasons'][season_index]['episodes'][episode_index] = episode if local_show['seasons'][season_index]['episodes'][episode_index].nil?
      end
    end
    local_shows[show_index] = local_show
  end
end

# Communicate with transmission
local_shows.each do |show|
  show['seasons'].each do |season|
    season['episodes'].each do |episode|
      unless episode['downloaded']
        torrent_page = agent.get episode['link']
        magnet_link = torrent_page.search('a.magnetlinkButton').attribute('href').text
        Trans::Api::Torrent.add_magnet magnet_link
        episode['downloaded'] = true
      end
    end
  end
end

# Save changes
File.open config_path + '/shows.yml', 'w' do |file|
  file.write Psych.dump local_shows
end
