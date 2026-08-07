#!/usr/bin/env ruby
# encoding: UTF-8

require 'json'
require 'fileutils'

DIR = File.dirname(__FILE__)
FAVICON_CACHE_FILE = File.join(DIR, 'favicon_cache.json')
KNOWN_URLS_FILE = File.join(DIR, 'known_urls.json')

puts "--- Rescanning for Missing Icons ---"

unless File.exist?(FAVICON_CACHE_FILE)
  puts "No cache file found."
  exit
end

cache = JSON.parse(File.read(FAVICON_CACHE_FILE))

# Identify icons that failed previously
failed_urls = cache.select { |k, v| v == 'failed' || v.nil? || v.strip.empty? }.keys

if failed_urls.empty?
  puts "No failed icons found! Everything is perfectly cached."
else
  puts "Found #{failed_urls.size} missing/failed icons."
  
  # Delete them from the cache so they will be fetched again
  failed_urls.each { |url| cache.delete(url) }
  File.write(FAVICON_CACHE_FILE, JSON.pretty_generate(cache))
  puts "Removed failed entries from the cache."
  
  # Delete known_urls.json to trick the generator into rebuilding the HTML
  File.delete(KNOWN_URLS_FILE) if File.exist?(KNOWN_URLS_FILE)
  puts "Reset known URLs tracker."
  
  # Trigger the main generator, which now has the Google fallback
  puts "Starting regeneration process..."
  Dir.chdir(DIR) do
    system("ruby generate_bookmarks.rb")
  end
end
