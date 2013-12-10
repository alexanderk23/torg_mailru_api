# TorgMailruApi

Товары@Mail.Ru (torg.mail.ru) Content API Wrapper for Ruby.

Torg.Mail.Ru Content API documentation is available [here](http://torg.mail.ru/info/217/).

[![Gem Version](https://badge.fury.io/rb/torg_mailru_api.png)](http://badge.fury.io/rb/torg_mailru_api)

## Installation

Add this line to your application's Gemfile:

    gem 'torg_mailru_api'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install torg_mailru_api

## Usage

``` ruby
require 'torg_mailru_api'

TorgMailruApi.configure do |c|
  c.access_token = 'YourSecretAccessToken'
end

TorgMailruApi.vendors.each do |vendor|
  p vendor.name
end

region = TorgMailruApi.region(310)
print region.id, " - ", region.name, "\n"
# 310 - Ростовская обл.

TorgMailruApi.region_suggest(:query => 'ростов').each do |region|
  print region.id, " - ", region.name, "\n"
end
# 1769 - Ростов
# 1833 - Ростов-на-Дону
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
