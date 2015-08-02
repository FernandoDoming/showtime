require 'open-uri'
require 'mechanize'

module Kat

  # Constants
  DOMAIN = 'http://kat.cr'

  ##### Kat::Parser
  class Parser

    # Accessors
    attr_reader :agent    # Agent to submit HTTP requests
    attr_reader :page

    # Constructor
    def initialize url = nil
      @agent = Mechanize.new
      unless url.nil?
        @page  = @agent.get url
      end
    end

    # Methods
    def parse url
      raise ParserError if @agent.nil?
      @page = @agent.get url
    end

    def show_title
      raise ParserError, 'call parse first' if @page.nil?
      @page.search('table.doublecelltable h1').first.text
    end

    def seasons
      @page.search 'table.doublecelltable br + h3'
    end

    def episodes_for_season season_element
      season_element.next_element.search 'div.infoList div.infoListCut'
    end

    def torrents_for_episode episode_id
      torrents_page = @agent.get "#{Kat::DOMAIN}/media/getepisode/#{episode_id}/"
      # Get page links for torrents
      torrents = torrents_page.search 'a.cellMainLink'
    end

    def get_magnet page
      magnet_page = @agent.get page
      magnet_page.search('a.magnetlinkButton').attribute('href').text
    end

    # Errors
    class ParserError < StandardError
    end

  end

  ##### Kat::Torrent
  class Torrent

    attr_reader :magnet
    attr_reader :page

    def initialize torrent_element = nil
      initialize_from_element torrent_element unless torrent_element.nil?
    end

    def initialize_from_element element
      @page   = element.attribute('href').text
      @magnet = Showtime::Client.instance.parser.get_magnet @page
    end

  end

  # Module methods
  # def Kat.method
  # end
end