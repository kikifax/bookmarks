#!/usr/bin/env ruby
# encoding: UTF-8

require 'uri'
require 'net/http'
require 'open-uri'
require 'base64'
require 'nokogiri'
require 'json'
require 'fileutils'

# --- Configuration ---
VERSION = "1.0.#{Time.now.strftime("%Y%m%d%H%M%S")}"
INPUT_FILES = Dir.glob(File.join(File.dirname(__FILE__), '*.md'))
OUTPUT_FILE = 'bookmarks.html'
FAVICON_CACHE_FILE = 'favicon_cache.json'

CSS_CONTENT = <<~CSS
/* Base styles */
body { 
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  margin: 0; 
  padding: 1.5rem; 
  background-color: #ffffff;
  color: #000000;
  transition: background-color 0.5s, color 0.5s;
}

/* Theme Definitions */
body.theme-classic-clean { background-color: #f8f9fa; color: #212529; }
body.theme-forest { background-color: #e6ffe6; color: #3d403d; }
body.theme-ocean-blue { background-color: #e0f2f7; color: #1a2e3a; }
body.theme-sunset-orange { background-color: #fff3e0; color: #3b2a1e; }
body.theme-deep-purple { background-color: #f3e5f5; color: #2e1a3a; }
body.theme-forest-green { background-color: #e8f5e9; color: #1b3d20; }
body.theme-warm-grey { background-color: #f5f5f5; color: #333333; }
body.theme-cyberpunk { background-color: #1a001a; color: #00ff00; }
body.theme-berry-pink { background-color: #fce4ec; color: #3a1a2e; }
body.theme-monochrome-dark { background-color: #212529; color: #e0e0e0; }
body.theme-high-contrast-bold { background-color: #000000; color: #00ffff; }
body.theme-gentle-gradient { background-color: #e0e0e0; color: #333333; }
body.theme-hacker-green { background-color: #0a0a0a; color: #00cc00; }

body.theme-hacker-green h2 { color: #00cc00; border-bottom-color: #00cc00; }
body.theme-hacker-green a { color: #00cc00; }
body.theme-hacker-green a:hover { color: #33ff33; }

/* Layout styles */
.masonry-container { position: relative; width: 100%; }
.category {
  position: absolute;
  background: rgba(255, 255, 255, 0.5);
  border: 1px solid #dee2e6;
  border-radius: 8px;
  padding: 1.2rem;
  box-shadow: 0 2px 4px rgba(0,0,0,0.05);
  box-sizing: border-box;
  transition: top 0.3s, left 0.3s;
}
body.theme-monochrome-dark .category,
body.theme-cyberpunk .category,
body.theme-hacker-green .category {
    background: rgba(0, 0, 0, 0.2);
    border-color: #495057;
}

h2 { font-size: 1.3rem; margin-top: 0; margin-bottom: 1rem; color: #007bff; border-bottom: 2px solid #007bff; padding-bottom: 0.5rem; }
ul { list-style: none; padding: 0; margin: 0; }
li { margin-bottom: 0.75rem; display: flex; align-items: center; }
a { color: #0056b3; text-decoration: none; line-height: 1.4; }
a:hover { text-decoration: underline; }
.favicon { width: 20px; height: 20px; margin-right: 12px; object-fit: contain; vertical-align: middle; border-radius: 3px; }
CSS

AVAILABLE_THEMES = ["theme-classic-clean", "theme-forest", "theme-ocean-blue", "theme-sunset-orange", "theme-deep-purple", "theme-forest-green", "theme-warm-grey", "theme-cyberpunk", "theme-berry-pink", "theme-monochrome-dark", "theme-high-contrast-bold", "theme-gentle-gradient", "theme-hacker-green"]
DEFAULT_THEME_CONFIG = 'theme-hacker-green'

ORDER_ARRAY_STRING = <<~CATEGORIES
coding
games
tools
personal, banking etc.
AI
media
watch
exercise
software, warez
learning
languages
random saves
process
CATEGORIES
ORDER_ARRAY = ORDER_ARRAY_STRING.split("\n").map(&:strip).reject(&:empty?)

JS_CONTENT = <<~JS
document.addEventListener("DOMContentLoaded", function() {
  // 1. Theme selection logic
  const availableThemes = #{AVAILABLE_THEMES.to_json};
  const defaultTheme = "#{DEFAULT_THEME_CONFIG}";
  const body = document.body;
  let selectedTheme = defaultTheme || availableThemes[Math.floor(Math.random() * availableThemes.length)];
  body.classList.add(selectedTheme);

  // 2. Masonry layout logic
  const container = document.querySelector('.masonry-container');
  if (!container) return;
  const items = Array.from(container.querySelectorAll('.category'));
  let resizeTimeout;

  function masonryLayout() {
    if (!items.length) return;
    const containerWidth = container.offsetWidth;
    const gap = 15;
    let numColumns = 4;
    if (containerWidth <= 600) numColumns = 1;
    else if (containerWidth <= 900) numColumns = 2;
    else if (containerWidth <= 1200) numColumns = 3;
    
    const colWidth = (containerWidth - (gap * (numColumns - 1))) / numColumns;
    items.forEach(item => { item.style.width = `${colWidth}px`; });
    const colHeights = Array(numColumns).fill(0);

    items.forEach(item => {
      let minColHeight = Math.min(...colHeights);
      let shortestColIndex = colHeights.indexOf(minColHeight);
      item.style.top = `${minColHeight}px`;
      item.style.left = `${shortestColIndex * (colWidth + gap)}px`;
      colHeights[shortestColIndex] += item.offsetHeight + gap;
    });
    container.style.height = `${Math.max(...colHeights)}px`;
  }
  
  function debouncedLayout() {
    clearTimeout(resizeTimeout);
    resizeTimeout = setTimeout(masonryLayout, 150);
  }
  window.addEventListener('resize', debouncedLayout);
  
  // 3. Lazy loading for images
  const lazyImages = Array.from(document.querySelectorAll("img.favicon[data-src]"));
  if ("IntersectionObserver" in window) {
    let lazyImageObserver = new IntersectionObserver(function(entries, observer) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          let lazyImage = entry.target;
          lazyImage.src = lazyImage.dataset.src;
          lazyImage.removeAttribute("data-src");
          lazyImage.addEventListener('load', debouncedLayout);
          lazyImageObserver.unobserve(lazyImage);
        }
      });
    });
    lazyImages.forEach(lazyImage => lazyImageObserver.observe(lazyImage));
  } else {
    lazyImages.forEach(lazyImage => {
      lazyImage.src = lazyImage.dataset.src;
      lazyImage.removeAttribute('data-src');
    });
    setTimeout(masonryLayout, 500);
  }
  
  setTimeout(masonryLayout, 50);
});
JS
def parse_bookmarks_tsv(content)
  bookmarks = []
  cleaned_content = content.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
  cleaned_content.each_line do |line|
    next if line.strip.empty? || line.strip.downcase.start_with?('title')
    parts = line.strip.split("\t", 4)
    if parts.length >= 2
      title = parts[0].strip
      url = parts[1].strip
      bookmarks << {title: title, url: url} if URI.regexp(['http', 'https']).match?(url)
    end
  end
  bookmarks
end

MAX_FAVICON_SIZE_BYTES = 50 * 1024 # 50 KB

def get_and_process_favicon(page_url)
  page_uri = URI.parse(page_url)
  best_favicon_url = nil
  fallback_favicon_url = nil

  # Step 1: Try to fetch the page and parse its HTML for <link rel="icon">
  begin
    Net::HTTP.start(page_uri.host, page_uri.port, use_ssl: page_uri.scheme == 'https', read_timeout: 3, open_timeout: 3) do |http|
      request = Net::HTTP::Get.new(page_uri)
      response = http.request(request)
      if response.is_a?(Net::HTTPSuccess)
        doc = Nokogiri::HTML(response.body)
        
        # Collect all potential favicons
        icons = doc.css("link[rel*='icon']")
        
        # Sort icons to prioritize smallest and 'image/x-icon'
        # The logic here is:
        # 1. Prefer 'image/x-icon' (ICO)
        # 2. Then by sizes, preferring smaller sizes
        # 3. Then by type, preferring PNG over others
        sorted_icons = icons.sort_by do |icon|
          rel = icon['rel'] || ''
          type = icon['type'] || ''
          sizes_attr = icon['sizes']
          
          size_value = 9999 # Default large size for sorting
          if sizes_attr && sizes_attr =~ /(\d+)x(\d+)/
            size_value = $1.to_i
          end
          
          # Priority: ICO > PNG > SVG > Others
          type_priority = case type
                          when 'image/x-icon' then 0
                          when 'image/png' then 1
                          when 'image/svg+xml' then 2
                          else 3
                          end
          
          # Priority: 'shortcut icon' > 'icon' (less important than type/size)
          rel_priority = rel.include?('shortcut icon') ? 0 : 1
          
          [type_priority, size_value, rel_priority]
        end

        sorted_icons.each do |icon_link|
          href = icon_link['href']
          if href
            candidate_uri = URI.join(page_uri, href)
            # Ensure it's an http/https URL
            if ['http', 'https'].include?(candidate_uri.scheme)
              best_favicon_url = candidate_uri.to_s
              break # Found the best candidate, stop looking
            end
          end
        end
      end
    end
  rescue StandardError => e
    # puts "Error fetching page for favicon discovery for #{page_url}: #{e.message}"
  end

  # Fallback to /favicon.ico if no specific link was found
  unless best_favicon_url
    fallback_favicon_url = URI.join(page_uri, '/favicon.ico').to_s
    best_favicon_url = fallback_favicon_url
  end

  # Step 2: Fetch the favicon image data
  begin
    # Use the determined best_favicon_url
    image_data = URI.open(best_favicon_url, 'rb', read_timeout: 3, open_timeout: 3).read
    
    # Check size limit
    if image_data.bytesize > MAX_FAVICON_SIZE_BYTES
      # puts "Favicon for #{page_url} exceeds size limit (#{image_data.bytesize} bytes), skipping."
      return nil # Too large, return nil so it's marked as 'failed'
    end

    ext = File.extname(URI.parse(best_favicon_url).path).delete('.').downcase
    mime_type = case ext
                when 'png' then 'image/png'; when 'jpg', 'jpeg' then 'image/jpeg'
                when 'gif' then 'image/gif'; when 'svg' then 'image/svg+xml'
                when 'ico' then 'image/x-icon'; else 'application/octet-stream'
                end
    return "data:#{mime_type};base64,#{Base64.strict_encode64(image_data)}"
  rescue OpenURI::HTTPError => e
    # puts "HTTP Error fetching favicon from #{best_favicon_url} for #{page_url}: #{e.message}"
  rescue StandardError => e
    # puts "Error fetching or processing favicon from #{best_favicon_url} for #{page_url}: #{e.message}"
  end
  nil # Return nil if anything failed
end

def load_favicon_cache
  File.exist?(FAVICON_CACHE_FILE) ? JSON.parse(File.read(FAVICON_CACHE_FILE)) : {}
end

def save_favicon_cache(cache)
  File.write(FAVICON_CACHE_FILE, JSON.pretty_generate(cache))
end

def generate_html(files)
  puts "Bookmarks Generator (v#{VERSION})"
  favicon_cache = load_favicon_cache
  puts "Loaded #{favicon_cache.size} favicons from cache."
  
  all_bookmarks = []
  files.each { |md_file| all_bookmarks.concat(parse_bookmarks_tsv(File.read(md_file, encoding: 'UTF-8')))}
  total_bookmarks = all_bookmarks.size
  puts "Found #{total_bookmarks} bookmarks to process."

  # Collect all unique URLs that need favicons
  unique_urls = all_bookmarks.map { |bm| bm[:url] }.uniq
  
  # Filter out URLs already in cache
  urls_to_fetch = unique_urls.reject { |url| favicon_cache.key?(url) }
  puts "Fetching favicons for #{urls_to_fetch.size} new URLs..."

  # Fetch favicons for new URLs
  urls_to_fetch.each_with_index do |url, index|
    print "\rFetching favicon for URL #{index + 1}/#{urls_to_fetch.size}..."
    favicon_cache[url] = get_and_process_favicon(url) || 'failed'
  end
  puts "\nFinished fetching new favicons."

  File.open(OUTPUT_FILE, 'w') do |file|
    file.puts "<!DOCTYPE html>"
    file.puts "<html lang='en'>"
    file.puts "  <head>"
    file.puts "    <meta charset='UTF-8'>"
    file.puts "    <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
    file.puts "    <title>Bookmarks (v#{VERSION})</title>"
    file.puts "    <style>#{CSS_CONTENT}</style>"
    file.puts "  </head>"
    file.puts "  <body>"
    file.puts "    <div class='masonry-container'>"

    sorted_files = files.sort_by do |file_path|
      category = File.basename(file_path, '.md')
      index = ORDER_ARRAY.index(category)
      index.nil? ? [1, category] : [0, index]
    end

    sorted_files.each do |md_file|
      category = File.basename(md_file, '.md').capitalize
      bookmarks = parse_bookmarks_tsv(File.read(md_file, encoding: 'UTF-8'))

      unless bookmarks.empty?
        file.puts "      <div class='category'>"
        file.puts "        <h2>#{category.gsub('"', '&quot;')}</h2>"
        file.puts "        <ul>"
        bookmarks.each do |bookmark|
          url = bookmark[:url]
          title = bookmark[:title]
          
          # Use the pre-fetched favicon data from the cache
          favicon_data = favicon_cache[url]
          file.puts "          <li>"
          if favicon_data && favicon_data != 'failed'
            file.puts "            <img data-src='#{favicon_data}' class='favicon' alt=''>"
          end
          file.puts "            <a href='#{url}' title='#{url}'>#{title}</a>"
          file.puts "          </li>"
        end
        file.puts "        </ul>"
        file.puts "      </div>"
      end
    end

    file.puts "    </div>"
    file.puts "    <script>#{JS_CONTENT}</script>"
    file.puts "  </body>"
    file.puts "</html>"
  end
  
  puts "\nFinished processing."
  save_favicon_cache(favicon_cache)
  puts "Successfully generated #{OUTPUT_FILE}"
end

# --- Main Execution ---
generate_html(INPUT_FILES)