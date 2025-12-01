#!/usr/bin/env ruby
# encoding: UTF-8

require 'uri'
require 'net/http'
require 'open-uri'
require 'base64'
require 'nokogiri'
require 'json'

# --- Configuration ---
INPUT_FILES = Dir.glob('*.md')
OUTPUT_FILE = 'bookmarks.html'
FAVICON_CACHE_FILE = 'favicon_cache.json'

ORDER_ARRAY_STRING = <<-CATEGORIES
coding
tools
games
personal, banking etc.
learning
languages
media
exercise
software, warez
watch
AI
random saves
process
CATEGORIES

ORDER_ARRAY = ORDER_ARRAY_STRING.split("\n").map(&:strip).reject(&:empty?)
# --- End Configuration ---

# Parses content assuming TSV format: Title\tURL\tDate\tNotes
def parse_bookmarks_tsv(content)
  bookmarks = []
  cleaned_content = content.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
  
  cleaned_content.each_line do |line|
    next if line.strip.empty? || line.strip.downcase.start_with?('title')
    parts = line.strip.split("\t", 4)
    if parts.length >= 2
      title = parts[0].strip
      url = parts[1].strip
      if URI.regexp(['http', 'https']).match?(url)
        bookmarks << {title: title, url: url}
      end
    end
  end
  bookmarks
end

# Fetches a favicon and returns it as a Base64 data URI
def get_favicon_base64(page_url)
  page_uri = URI.parse(page_url)
  favicon_url = nil

  begin
    # 1. Fetch the page and parse it for link tags
    # Use Net::HTTP.start for better control over timeouts
    Net::HTTP.start(page_uri.host, page_uri.port,
                    use_ssl: page_uri.scheme == 'https',
                    read_timeout: 5, # seconds
                    open_timeout: 5) do |http|
      request = Net::HTTP::Get.new(page_uri)
      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        doc = Nokogiri::HTML(response.body)
        icon_link = doc.at_css("link[rel='icon']") || doc.at_css("link[rel='shortcut icon']")
        if icon_link && icon_link['href']
          favicon_uri = URI.join(page_uri, icon_link['href'])
          favicon_url = favicon_uri.to_s
        end
      end
    end
  rescue StandardError => e
    # puts "  Error fetching page for favicon (ignoring): #{e.message}"
  end

  # 2. If no link tag found, try the default favicon.ico location
  favicon_url ||= URI.join(page_uri, '/favicon.ico').to_s

  # 3. Fetch the favicon image and Base64 encode it
  begin
    # Use OpenURI with a timeout
    image_data = URI.open(favicon_url, 'rb', read_timeout: 5, open_timeout: 5).read
    
    # Determine MIME type more robustly
    ext = File.extname(URI.parse(favicon_url).path).delete('.').downcase
    mime_type = case ext
                when 'png' then 'image/png'
                when 'jpg', 'jpeg' then 'image/jpeg'
                when 'gif' then 'image/gif'
                when 'svg' then 'image/svg+xml'
                when 'ico' then 'image/x-icon'
                else 'application/octet-stream' # Generic binary data
                end
    
    return "data:#{mime_type};base64,#{Base64.strict_encode64(image_data)}"
  rescue StandardError => e
    # puts "  Error fetching/encoding favicon: #{e.message}"
    return nil # Return nil if any part of fetching/encoding fails
  end
end

def load_favicon_cache
  if File.exist?(FAVICON_CACHE_FILE)
    JSON.parse(File.read(FAVICON_CACHE_FILE))
  else
    {}
  end
end

def save_favicon_cache(cache)
  File.write(FAVICON_CACHE_FILE, JSON.pretty_generate(cache))
end

def generate_html(files)
  puts "Starting HTML generation process..."
  puts "Loading favicon cache from '#{FAVICON_CACHE_FILE}'..."
  favicon_cache = load_favicon_cache # CRITICAL FIX: Load the cache here!
  puts "Favicon cache loaded. Contains #{favicon_cache.size} entries."
  
  # Sort files based on ORDER_ARRAY
  sorted_files = files.sort_by do |file|
    category = File.basename(file, '.md')
    index = ORDER_ARRAY.index(category)
    index.nil? ? [1, category] : [0, index]
  end

  # --- Progress Counter Setup ---
  all_bookmarks = []
  puts "Reading all bookmarks from Markdown files..."
  sorted_files.each do |md_file|
    content = File.read(md_file, encoding: 'UTF-8')
    all_bookmarks.concat(parse_bookmarks_tsv(content))
  end
  total_bookmarks = all_bookmarks.size
  processed_count = 0
  puts "Found #{total_bookmarks} unique bookmarks to process."
  # ------------------------------

  File.open(OUTPUT_FILE, 'w') do |file|
    # HTML and CSS structure
    file.puts '<!DOCTYPE html>'
    file.puts '<html lang="en">'
    file.puts '<head>'
    file.puts '  <meta charset="UTF-8">'
    file.puts '  <meta name="viewport" content="width=device-width, initial-scale=1.0">'
    file.puts '  <title>Bookmarks</title>'
    file.puts '  <style>'
    file.puts '    :root { --accent-color: #007bff; --text-color: #343a40; --bg-color: #f8f9fa; --card-bg: #ffffff; --card-border: #dee2e6; }'
    file.puts '    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.4; color: var(--text-color); background-color: var(--bg-color); margin: 0; padding: 1rem; -webkit-font-smoothing: antialiased; }'
    file.puts '    .masonry-container { column-count: 4; column-gap: 1rem; }'
    file.puts '    .category { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 6px; padding: 0.75rem; box-shadow: 0 2px 4px rgba(0,0,0,0.05); break-inside: avoid; margin-bottom: 1rem; }'
    file.puts '    h2 { font-size: 1rem; font-weight: 500; color: var(--accent-color); margin: 0 0 0.75rem 0; border-bottom: 1px solid var(--card-border); padding-bottom: 0.5rem; }'
    file.puts '    ul { list-style: none; padding: 0; margin: 0; }'
    file.puts '    li { display: flex; align-items: center; margin-bottom: 0.25rem; }'
    file.puts '    .favicon { width: 16px; height: 16px; margin-right: 6px; }'
    file.puts '    a { font-size: 0.875rem; color: var(--text-color); text-decoration: none; display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; transition: color 0.2s ease-in-out; }'
    file.puts '    a:hover { color: var(--accent-color); }'
    file.puts '    @media (max-width: 1400px) { .masonry-container { column-count: 3; } }'
    file.puts '    @media (max-width: 992px) { .masonry-container { column-count: 2; } }'
    file.puts '    @media (max-width: 576px) { .masonry-container { column-count: 1; } }'
    file.puts '  </style>'
    file.puts '</head>'
    file.puts '<body>'
    file.puts '  <div class="masonry-container">'

    sorted_files.each do |md_file|
      category = File.basename(md_file, '.md').capitalize
      # HTML escape category name for use in HTML content
      escaped_category = category.gsub('"', '&quot;').gsub("'", '&apos;')

      content = File.read(md_file, encoding: 'UTF-8')
      
      bookmarks = parse_bookmarks_tsv(content)

      unless bookmarks.empty?
        file.puts '      <div class=\'category\'>'
        file.puts "        <h2>#{escaped_category}</h2>"
        file.puts '        <ul>'
        bookmarks.each do |bookmark|
          processed_count += 1
          
          favicon_data = favicon_cache[bookmark[:url]]
          unless favicon_data
            puts "Fetching favicon for \"#{bookmark[:title]}\" from #{bookmark[:url]} (##{processed_count}/#{total_bookmarks})..."
            favicon_data = get_favicon_base64(bookmark[:url])
            favicon_cache[bookmark[:url]] = favicon_data if favicon_data
          else
            puts "Using cached favicon for \"#{bookmark[:title]}\" from #{bookmark[:url]} (##{processed_count}/#{total_bookmarks})..."
          end
          
          file.puts '          <li>'
          if favicon_data
            file.puts "            <img src='#{favicon_data}' class='favicon' alt=''>"
          end
          file.puts "            <a href='#{bookmark[:url]}' target='_blank' title='#{bookmark[:url]}'>#{bookmark[:title]}</a>"
          file.puts '          </li>'
        end
        file.puts '        </ul>'
        file.puts '      </div>'
      end
    end

    file.puts '  </div>'
    file.puts '</body>'
    file.puts '</html>'
  end

  puts "Saving favicon cache to '#{FAVICON_CACHE_FILE}'..."
  save_favicon_cache(favicon_cache)
  puts "Favicon cache saved. Total entries: #{favicon_cache.size}."
end

# --- Main Execution ---
generate_html(INPUT_FILES)

puts "\nSuccessfully generated #{OUTPUT_FILE}"