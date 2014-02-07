require 'nokogiri'
require 'rest-client'
require 'uri'

class FreshDirect

  FRESH_DIRECT_BASE_URL = "https://www.freshdirect.com"
  FRESH_DIRECT_PRODUCT_URL = "#{FRESH_DIRECT_BASE_URL}/product.jsp"
  FRESH_DIRECT_CATEGORY_URL = "#{FRESH_DIRECT_BASE_URL}/category.jsp"
  FRESH_DIRECT_COOKIE_URL = "#{FRESH_DIRECT_BASE_URL}/welcome.jsp"
  FRESH_DIRECT_CART_URL = "#{FRESH_DIRECT_BASE_URL}/view_cart.jsp"

  FRESH_DIRECT_PRODUCT_FORM_REGEXP = /<form id='product_form'.*?<\/form>/m
  FRESH_DIRECT_CATEGORY_FORM_REGEXP = /<form name="groceryForm".*?<\/form>/m
  FRESH_DIRECT_PRODUCT_QUANTITY_FIELD_NAME = 'quantity_big'
  FRESH_DIRECT_CATEGORY_QUANTITY_FIELD_NAME = 'quantity'

  def initialize(fd_array)
    @orders = process_encodings fd_array
  end

  def get_cookies
    establish_session
    process_orders
    return_cookies
  end

  def return_cookies
    @session_cookies
  end

  def process_encodings(fd_array)
    fd_array.select do |fd|
      fd["url"] =~ /https.+www\.freshdirect\.com.+(product|category)/
    end.map do |fd|
      new_url = URI.unescape(fd["url"])
      fd["url"] = new_url
      fd["type"] = new_url.match(/\w*(?=.jsp)/)[0]
      fd["args"] = {}

      args = fd["url"].split("?")[1].split("&")
      args.each do |arg|
        key, value = arg.split "="
        fd["args"][key] = value if ["catId", "prodCatId", "productId"].include?(key)
      end
      fd
    end
  end

  def establish_session
    response = RestClient.get FRESH_DIRECT_COOKIE_URL
    cookies = response.cookies

    @session_cookies = cookies
  end

  # 1. How to send parameters as POST data?
  # 2. What cookies are the minimum necessary to maintain state?
  # 3. What are the post parameters required?
  def add_item item
    payload = parse_page item
    unless payload.nil?
      if item["type"] == "category"
        url = "#{FRESH_DIRECT_CATEGORY_URL}?#{URI.encode_www_form(item["args"])}"
      elsif item["type"] == "product"
        url = "#{FRESH_DIRECT_PRODUCT_URL}?#{URI.encode_www_form(item["args"])}"
      end
      RestClient.post url,
                      payload,
                      {
                        cookies: @session_cookies,
                        origin: FRESH_DIRECT_BASE_URL,
                        referer: url
                      } do |a, b, c|
                        # Ignore redirects
                      end
    end
  end

  def parse_page item
    html = RestClient.get(item["url"]).force_encoding("ISO-8859-1").encode("utf-8", replace: nil)
    if item["type"] == "category"
      regexp = FRESH_DIRECT_CATEGORY_FORM_REGEXP
      quantity_field = FRESH_DIRECT_CATEGORY_QUANTITY_FIELD_NAME
    elsif item["type"] == "product"
      regexp = FRESH_DIRECT_PRODUCT_FORM_REGEXP
      quantity_field = FRESH_DIRECT_PRODUCT_QUANTITY_FIELD_NAME
    end

    match = regexp.match(html)
    return nil if match.nil?

    rel_form = match[0]
    root = Nokogiri::HTML(rel_form).root()

    input_fields = root.css('input')

    input_hash = Hash.new
    input_fields.each do |field|
      if field["value"]
        input_hash[field["name"]] = URI.encode field["value"]
      end
    end

    # Valid category request must have synced product quantity in the
    # fields below
    if item["type"] == "category"
      synced_lower_id = /syncProdIdx.*?(\d+)/.match(rel_form)[1]
      input_hash["quantity_#{synced_lower_id}"] = item["qty"].empty? ? "1" : item["qty"]
      input_hash['PRICE'] = /groceryStyleRegularOnly.*(\$\d+\.\d+)/.match(rel_form)[1]
    elsif item["type"] == "product"
      input_hash['PRICE'] = /productPageSinglePrice.*(\$\d+\.\d+)/.match(rel_form)[1]
    end
    print item
    input_hash[quantity_field] = item["qty"].empty? ? "1" : item["qty"]
    input_hash["quantity"] = item["qty"].empty? ? "1" : item["qty"]
    hash_to_params input_hash
  end

  def hash_to_params(hash)
    URI.encode_www_form(hash)
  end

  def process_orders
    @orders.each do |order|
      add_item order
    end
  end

end
