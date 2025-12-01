#!/usr/bin/env ruby
# encoding: UTF-8

require 'nokogiri'
require 'fileutils'
require 'time'

# --- Configuration ---
HTML_FILE = 'booky.html'
OUTPUT_DIR = '.'
# --- End Configuration ---

puts "Starting import from #{HTML_FILE}..."

# Read and parse the HTML file
begin
  doc = File.open(HTML_FILE) { |f| Nokogiri::HTML(f) }
rescue Errno::ENOENT
  puts "Error: #{HTML_FILE} not found in the current directory."
  exit
end

# Find all category list items
categories = doc.css('li.category')

if categories.empty?
  puts "No categories found in the HTML file. Please check the file's structure."
  exit
end

puts "Found #{categories.count} categories. Processing..."

categories.each do |category_element|
  # Extract category name from the h2 title attribute
  category_name = category_element.at_css('h2.category__name')&.attr('title')&.strip

  if category_name.nil? || category_name.empty?
    puts "Skipping a category because its name could not be found."
    next
  end

  puts "  Processing category: #{category_name}" 
  
  # Define the output .md file for this category
  output_md_file = File.join(OUTPUT_DIR, "#{category_name}.md")
  
  # Find all bookmarks within this category
  bookmarks = category_element.css('li.bookmark a.bookmark__link')
  
  if bookmarks.empty?
    puts "    No bookmarks found in this category."
    next
  end
  
  puts "    Found #{bookmarks.count} bookmarks. Appending to #{output_md_file}..."
  
  # Open the file in append mode
  File.open(output_md_file, 'a') do |file|
    bookmarks.each do |link|
      url = link.attr('href')
      title = link.text.strip
      
      # Sanitize title by replacing tabs with spaces
      title.gsub!("\t", " ")

      # Get current date and time
      date = Time.now.strftime('%Y-%m-%d %H:%M')
      
      # Notes are empty for this import
      notes = ''
      
      # Create TSV line
      tsv_line = [title, url, date, notes].join("\t") + "\n"
      
      # Append the line to the category's .md file
      file.write(tsv_line)
    end
  end
end

puts "Import complete."
