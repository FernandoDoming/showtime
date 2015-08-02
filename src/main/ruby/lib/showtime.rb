require_relative 'kat'
require 'singleton'
require 'psych'
require 'trans-api'
require 'pry'

module Showtime

  ##### Showtime::Client
  class Client
    include Singleton

    # Constants
    CONFIG_PATH           = File.expand_path('../../resources/config/', File.dirname(__FILE__))

    # Accessors
    attr_reader :subscriptions
    attr_reader :local_shows
    attr_reader :parser
    attr_accessor :shows

    # Constructor
    def initialize
      @subscriptions     = Psych.load_file "#{CONFIG_PATH}/subscriptions.yml"
      @local_shows       = Psych.load_file "#{CONFIG_PATH}/shows.yml"
      @transmission_opt  = Psych.load_file "#{CONFIG_PATH}/transmission.yml"
      @parser            = Kat::Parser.new               # TODO make source agnostic
      @shows             = []

      # Initialize to empty array if file could not be loaded or it's empty
      @local_shows   = [] if @local_shows.nil? || @local_shows == false
      self.set_transmission_options @transmission_opt
    end

    ### Methods
    def set_transmission_options options
      options = options.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}     # Convert string keys to symbol keys
      Trans::Api::Client.config = options
    end

    # TODO improve
    # Get changes from remote
    def pull
      local_shows  = @local_shows.map { |show| Showtime::Helper.show_to_model show }
      remote_shows = @shows

      remote_shows.each_with_index do |show, show_index|
        local_shows[show_index] = show if local_shows[show_index].nil?    # A new show has been added
        local_show = local_shows[show_index]

        show.seasons.each_with_index do |season, season_index|
          local_show.seasons = [] if local_show.seasons.nil?
          local_show.seasons[season_index] = season if local_show.seasons[season_index].nil?
          local_season = local_show.seasons[season_index]

          season.episodes.each_with_index do |episode, episode_index|
            local_show.seasons[season_index].episodes = [] if local_show.seasons[season_index].episodes.nil?
            local_show.seasons[season_index].episodes[episode_index] = episode if local_show.seasons[season_index].episodes[episode_index].nil?

            local_episode = local_show.seasons[season_index].episodes[episode_index]
            unless local_episode.link == episode.link
              local_episode.title      = episode.title
              local_episode.link       = episode.link
              local_episode.id         = episode.id
              local_episode.downloaded = episode.downloaded
              local_episode.torrent    = episode.torrent
              local_show.seasons[season_index].episodes[episode_index] = local_episode              
            end
          end
        end
        local_shows[show_index] = local_show
      end
      local_shows
    end

    def download_new shows
      shows.each do |show|
        show.seasons.each do |season|
          season.episodes.each do |episode|
            if !episode.downloaded && episode.torrent
              episode.download
            end
          end if season.episodes
        end if show.seasons
      end
    end

    def save shows
      File.open "#{CONFIG_PATH}/shows.yml", 'w' do |file|
        file.write Psych.dump(shows.map { |show| show.to_hash })
      end
    end

  end

  ##### Showtime::Helper
  class Helper

    def self.show_to_model show_hash
      model          = Showtime::Show.new
      model.title    = show_hash['title']
      model.link     = show_hash['link']
      model.seasons  = show_hash['seasons'].map{ |season| Showtime::Helper.season_to_model season } if show_hash['seasons']
      model
    end

    def self.season_to_model season_hash
      model          = Showtime::Season.new
      model.title    = season_hash['title']
      model.episodes = season_hash['episodes'].map { |episode| Showtime::Helper.episode_to_model episode } if season_hash['episodes']
      model
    end

    def self.episode_to_model episode_hash
      model            = Showtime::Episode.new
      model.id         = episode_hash['id']
      model.title      = episode_hash['title']
      model.link       = episode_hash['link']
      model.downloaded = episode_hash['downloaded']
      model.torrent    = episode_hash['torrent']
      model
    end

    def self.normalize show
      show.remove_parser!
      show.seasons.each do |season|
        season.remove_parser!
        season.remove_season_element!
        season.episodes.each do |episode|
          episode.remove_torrents!
          episode.remove_torrent!
        end
      end
    end

  end

  ##### Showtime::Show
  class Show

    # Accessors
    attr_accessor :title
    attr_accessor :link
    attr_accessor :seasons

    # Constructor
    def initialize url = nil
      initialize_from_url url unless url.nil?
    end

    # Methods
    def initialize_from_url url
      @parser   = Showtime::Client.instance.parser
      @parser.parse url

      @link     = url
      @title    = @parser.show_title
      @seasons  = self.get_all_seasons
    end

    def add_season season
      @seasons << season
    end

    def get_all_seasons
      @seasons = []
      @parser.seasons.reverse_each do |season_element|
        @seasons << Showtime::Season.new(season_element)
      end
      @seasons
    end

    def to_hash
      hash = {
        'title'   => @title,
        'link'    => @link,
        'seasons' => @seasons ? @seasons.map { |e| e.to_hash } : nil
      }
    end

    def remove_parser!
      remove_instance_variable(:@parser)
    end

  end

  ##### Showtime::Season
  class Season

    # Accessors
    attr_accessor :title
    attr_accessor :episodes

    # Constructor
    def initialize season_element = nil
      initialize_from_element season_element unless season_element.nil?
    end

    # Methods
    def initialize_from_element element
      @parser         = Showtime::Client.instance.parser
      @season_element = element
      @title          = element.text
      @episodes       = self.get_all_episodes
    end

    def add_episode episode
      @episodes << episode
    end

    def get_all_episodes
      @episodes = []
      @parser.episodes_for_season(@season_element).reverse_each do |episode_element|
        @episodes << Showtime::Episode.new(episode_element)
      end
      @episodes
    end

    def to_hash
      hash = {
        'title'    => @title,
        'episodes' => @episodes ? @episodes.map { |e| e.to_hash } : nil
      }
    end

    def remove_parser!
      remove_instance_variable(:@parser)
    end

    def remove_season_element!
      remove_instance_variable(:@season_element)
    end

  end

  ##### Showtime::Episode
  class Episode

    # Accessors
    attr_accessor :id
    attr_accessor :title
    attr_accessor :link
    attr_accessor :downloaded
    attr_accessor :torrent

    # Constructor
    def initialize episode_element = nil
      initialize_from_element episode_element unless episode_element.nil?
    end

    # Methods
    def initialize_from_element element
      episode_id  = element.attribute('onclick').text.scan(/\d+/).first
      @id         = episode_id
      @title      = element.search('.versionsEpName').first.text
      torrents    = Showtime::Client.instance.parser.torrents_for_episode episode_id

      unless torrents.empty?
        @torrent    = Showtime::Criteria.new(torrents).best
        @link       = @torrent.page
        @downloaded = false
      end
    end

    def to_hash
      hash = {
        'id'         => @id,
        'title'      => @title,
        'link'       => @link,
        'torrent'    => @torrent,
        'downloaded' => @downloaded
      }
    end

    def download
      Trans::Api::Torrent.add_magnet self.torrent.magnet
      self.downloaded = true   
    end

    def remove_torrents!
      remove_instance_variable(:@torrents) if @torrents
    end

    def remove_torrent!
      remove_instance_variable(:@torrent) if @torrent
    end

  end

  ##### Showtime::Criteria
  class Criteria

    # Constructor
    def initialize torrents
      @torrents = torrents
    end

    # Methods
    # TODO implement decission algorithm
    def best
      Kat::Torrent.new @torrents.first
    end
  end
  
end