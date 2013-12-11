# coding: utf-8

require 'faraday'
require 'faraday_middleware'
require 'ostruct'
require "torg_mailru_api/version"

module TorgMailruApi

  ENDPOINT_URI = "http://content.api.torg.mail.ru/#{API_VERSION}"

  module Configuration
    attr_accessor :access_token, :cache, :proxy, :logger, :adapter
    def configure
      yield self
    end
  end

  module Connection
    def connection
      raise "No access token" if access_token.nil?
      @connection ||= begin
        conn = Faraday.new ENDPOINT_URI do |c|
          c.use Faraday::Response::RaiseError
          c.use :instrumentation
          c.response :json, content_type: 'application/json'
          c.response :caching, cache, strip_params: access_token unless cache.nil?
          c.response :logger, logger unless logger.nil?
          c.adapter adapter.nil? ? Faraday.default_adapter : adapter
          c.proxy proxy if not proxy.nil?
          c.headers = {
            'Accept' => 'application/json',
            'Authorization' => access_token
          }
        end
        conn
      end
    end

    def get resource, params=nil
      response = connection.get "#{resource}.json", params
      response.body
    end
  end

  module APIRequest

    class DeepOpenStruct < OpenStruct

      def to_h
        convert_to_hash_recursive self.dup
      end

      def self.load item
        raise ArgumentError, "DeepOpenStruct must be passed a Hash or Array" unless(item.is_a?(Hash) || item.is_a?(Array))
        self.convert_from_hash_recursive item
      end

      private

      def self.convert_from_hash_recursive obj
        result = obj
        case result
          when Hash
            result = result.dup
            result.each do |k,v|
              result[k] = convert_from_hash_recursive(v)
            end
            result = DeepOpenStruct.new result
          when Array
            result = result.map { |v| convert_from_hash_recursive(v) }
        end
        result
      end

      def convert_to_hash_recursive obj
        result = obj
        case result
          when OpenStruct
            result = result.marshal_dump
            result.each do |k,v|
              result[k] = convert_to_hash_recursive(v)
            end
          when Array
            result = result.map { |v| convert_to_hash_recursive(v) }
        end
        result
      end
    end

    # Рекурсивная декамелизация ключей хеша
    def decamelize_hash_keys value
      case value
        when Array
          value.map { |v| decamelize_hash_keys(v) }
        when Hash
          Hash[value.map { |k, v| [ k.scan(/[A-Z][a-z]*|[a-z]+/).join('_').downcase, decamelize_hash_keys(v) ] }]
        when String
          value.gsub(/\s{2,}|[\r\n]/, ' ').strip
        else
          value
       end
    end

    # Запрос к API
    # @param [String] resource Ресурс API, к которому осуществляется запрос
    # @param [Hash] params Хеш параметров
    # @return [DeepOpenStruct] Результат запроса
    def get resource, params=nil
      response = super
      hash = decamelize_hash_keys response[response.keys.first]
      DeepOpenStruct.load hash
    end

    # Вспомогательная функция для преобразования ответа API в листинг
    # @param [String] resource Ресурс API, к которому осуществляется запрос
    # @param [Hash] params Хеш параметров
    # @return [Listing] Листинг
    def listing resource, params=nil
      Listing.new resource, params
    end

  end

  class Listing
    include Enumerable
    include TorgMailruApi

    def initialize resource, params=nil
        @resource = resource
        @params = params.nil? ? {} : params
        @params[:page] = @params.fetch(:page, 1)
        @items = []
        @more = true
    end

    def each
      return to_enum(:each) unless block_given?
      while true
        break unless fetch_next_page if @items.empty?
        yield @items.shift
      end
    end

    def fetch_next_page
      if @more
        r = TorgMailruApi.get @resource, @params
        @more = (r.results_total-r.results_per_page*r.page) > 0
        @items = r.listing
        @params[:page] += 1
        true
      end
    end
  end

  module APIMethods

    # @!macro api_method
    #   @param [Hash] params Хеш параметров
    # @!macro geodependent
    #   @note Ресурс является геозависимым.
    #   @option params [Integer] :geo_id Идентификатор региона (обязательно!)
    # @!macro returns_listing
    #   @note Ресурс в ответе возвращает листинг.
    #   @return [Listing] Листинг
    # @!macro returns_object
    #   @return [DeepOpenStruct] Объект
    # @!macro paginated
    #   @option params [Integer] :page (1) Номер страницы
    #   @option params [Integer] :results_per_page (10) Количество результатов на страницу (max: 30)
    # @!macro default_sort_order
    #   @option params [Symbol] :sort_order (:desc) Направление сортировки (:asc — по возрастанию; :desc — по убыванию)
    # @!macro user_location
    #   @option params [Float] :latitude Широта точки нахождения пользователя
    #   @option params [Float] :longitude Долгота точки нахождения пользователя
    # @!macro category_id
    #   @param [Integer] category_id Идентификатор товарной категории
    # @!macro model_id
    #   @param [Integer] model_id Идентификатор модели
    # @!macro offer_id
    #   @param [Integer] offer_id Идентификатор товарного предложения
    # @!macro seller_id
    #   @param [Integer] seller_id Идентификатор магазина
    # @!macro region_id
    #   @param [Integer] region_id Идентификатор региона
    # @!macro vendor_id
    #   @param [Integer] vendor_id Идентификатор производителя

    # @!group Товарные категории

    # Список категорий: получение списка товарных категорий верхнего уровня.
    # @macro api_method
    # @macro geodependent
    # @macro paginated
    # @macro returns_listing
    def categories params
      listing "category", params
    end

    # Список подкатегорий: получение списка подкатегорий для товарной категории.
    # @macro api_method
    # @macro geodependent
    # @macro category_id
    # @option params [Symbol] :type (:all) Фильтрация выходных данных по типу товарной категории (:all | :model | :parameterized | :general)
    # @option params [Integer] :page (1) Номер страницы
    # @option params [Integer] :results_per_page (выводятся все результаты) Количество результатов на страницу (max: 30)
    # @macro returns_listing
    def category_children category_id, params
      listing "category/#{category_id}/children", params
    end

    # Информация о категории: получение информации о товарной категории.
    # @macro api_method
    # @macro geodependent
    # @macro category_id
    # @macro returns_object
    def category category_id, params
      get "category/#{category_id}", params
    end

    # Список параметров категории: получение списка параметров товарной категории.
    # @macro api_method
    # @macro category_id
    # @option params [Symbol] :parameter_set (:popular) Тип набора параметров категории (:popular — популярные; :all — все)
    # @macro returns_object
    def category_parameters category_id, params=nil
      get "category/#{category_id}/parameters", params
    end

    # Список моделей категории: получение списка моделей в модельной товарной категории.
    # @note Для обычных категорий ресурс возвращает ошибку.
    # @macro api_method
    # @macro geodependent
    # @macro category_id
    # @option params [Integer] :vendor_id Идентификатор производителя
    # @option params [Symbol] :sort (:popular) Тип сортировки моделей (:date — сортировка по новизне; :popular — сортировка по популярности; :price — сортировка по цене)
    # @macro default_sort_order
    # @macro returns_listing
    def category_models category_id, params
      listing "category/#{category_id}/models", params
    end

    # Список товарных предложений категории: получение списка товарных предложений в обычной товарной категории.
    # @note Для модельных и параметризированных категорий ресурс возвращает ошибку.
    # @macro api_method
    # @macro category_id
    # @macro geodependent
    # @option params [Symbol] :sort (:auction) Тип сортировки предложений (:auction — по убыванию ставки; :price — сортировка по цене)
    # @macro default_sort_order
    # @macro paginated
    # @macro returns_listing
    def category_offers category_id, params
      listing "category/#{category_id}/offers", params
    end

    # Список хитов продаж категории: получение списка 50 моделей-хитов продаж модельной товарной категории.
    # @note Список отсортирован по степени убывания популярности у покупателей.
    # @note Для обычных категорий ресурс возвращает ошибку.
    # @macro api_method
    # @macro category_id
    # @macro geodependent
    # @macro returns_object
    def category_hits category_id, params
      get "category/#{category_id}/hits", params
    end

    # Список новинок категории: получение списка моделей в модельной товарной категории.
    # @note Для обычных категорий ресурс возвращает ошибку.
    # @macro api_method
    # @macro category_id
    # @macro geodependent
    # @option params [Symbol] :sort (:popular) Тип сортировки моделей (:popular — сортировка по популярности; :price — сортировка по цене)
    # @macro default_sort_order
    # @macro paginated
    # @macro returns_listing
    def category_newmodels category_id, params
      listing "category/#{category_id}/newmodels", params
    end

    # @!group Модели товаров

    # Информация о модели: получение информации об указанной модели.
    # @macro api_method
    # @macro model_id
    # @macro geodependent
    # @macro returns_object
    def model model_id, params
      get "model/#{model_id}", params
    end

    # Список характеристик модели: получение списка характеристик указанной модели.
    # @macro api_method
    # @macro model_id
    # @option params :parameter_set [Symbol] (:popular) Тип набора параметров категории (:popular — популярные, :all — все)
    # @macro returns_object
    def model_parameters model_id, params=nil
      get "model/#{model_id}/parameters", params
    end

    # Список предложений модели: получение списка товарных предложений указанной модели.
    # @macro api_method
    # @macro model_id
    # @macro geodependent
    # @option params [Symbol] :sort (:auction) Тип сортировки предложений (:auction — по убыванию ставки; :price — по цене,
    #   :rating — по рейтингу магазина + цене, :range — по расстоянию до ближайшей точки продаж (при указании местоположения пользователя)).
    #   * Если у параметра :sort указано значение :price, сортировка по возрастанию;
    #   * если у параметра :sort указано значение :rating, сортировка по убыванию;
    #   * если у параметра :sort указано значение :range, сортировка по возрастанию.
    # @option params [Symbol] :sort_order (:desc) Направление сортировки (:asc — по возрастанию; :desc — по убыванию).
    #   Задается только в том случае, если у параметра :sort указано значение :price
    # @macro paginated
    # @macro user_location
    # @macro returns_listing
    def model_offers model_id, params
      listing "model/#{model_id}/offers", params
    end

    # Список точек продаж модели: получение списка точек продаж указанной модели.
    # @macro api_method
    # @macro model_id
    # @macro geodependent
    # @macro paginated
    # @macro user_location
    # @macro returns_listing
    def model_outlets model_id, params
      listing "model/#{model_id}/outlets", params
    end

    # @!group Товарные предложения

    # Информация о товарном предложении: получение расширенной информации об указанном товарном предложении магазина.
    # @macro api_method
    # @macro offer_id
    # @macro returns_object
    def offer offer_id, params=nil
      get "offer/#{offer_id}", params
    end

    # @!group Поиск

    # Полнотекстовый поиск: получение списка моделей и товарных предложений, удовлетворяющих строке запроса.
    # @macro api_method
    # @macro geodependent
    # @option params [String] :query Поисковый запрос (обязательно!)
    # @option params [Integer] :category_id Фильтрация результатов поиска по товарной категории
    # @option params [Integer] :seller_id Фильтрация результатов поиска по магазину
    # @option params [Integer] :price_min Фильтрация результатов поиска по минимальной цене товарных предложений
    # @option params [Integer] :price_max Фильтрация результатов поиска по максимальной цене товарных предложений
    # @option params [Symbol] :sort (:relevance) Тип сортировки результатов поиска (:price — сортировка по возрастанию цены, :relevance — по релевантности)
    # @macro paginated
    # @macro returns_listing
    def search params
      listing "search", params
    end

    # Параметрический поиск: получение списка моделей категории, удовлетворяющих набору заданных параметров.
    # @macro api_method
    # @macro geodependent
    # @option params [String] &lt;parameter_id&gt; Параметр товарной категории. В запросе вместо <parameter_id> указыватся id параметра.
    #   Список параметров и их id для определенной товарной категории можно получить с помощью ресурса "Список параметров категории".
    #   Значение зависит от типа выбранного параметра категории:
    #   * тип параметра numeric — числовое значение <value> или числовой диапазон, значения границ которого разделяются запятой "<min_value>,<max_value>";
    #   * тип параметра enum — список идентификаторов допустимых значений параметра, разделенный запятыми, "<value1_id>,<value2_id>,<value3_id>", где <valueN_id> — идентификатор значения;
    #   * тип параметра bool — допустимые значения параметра: "true" и "false".
    # @option params [Symbol] :sort (:popular) Тип сортировки результатов поиска (:date — по новизне; :popular — по популярности; :price — по цене)
    # @macro default_sort_order
    # @macro paginated
    # @macro returns_listing
    def category_filter category_id, params
      listing "category/#{category_id}/filter", params
    end

    # @!group Отзывы

    # Отзывы о магазине: получение списка отзывов о магазине.
    # @macro api_method
    # @option params [Symbol] :sort (:date) Тип сортировки отзывов (:mark — по оценке пользователя; :date — по дате добавления отзыва; :valuable — по оценке полезности отзыва)
    # @macro default_sort_order
    # @option params [Integer,Symbol] :mark (:all) Фильтрация отзывов по оценке магазина (1, 2, 3, 4, 5; :all — все значения)
    # @option params [Integer] :page (1) Номер страницы
    # @option params [Integer] :results_per_page (выводятся все результаты) Количество результатов на страницу (max: 30)
    # @macro returns_listing
    def seller_reviews seller_id, params
      listing "seller/#{seller_id}/reviews", params
    end

    # @!group Магазины

    # Информация о магазине: получение информации о выбранном магазине.
    # @macro seller_id
    # @macro returns_object
    def seller seller_id
      get "seller/#{seller_id}"
    end

    # Список точек продаж магазина: получение списка точек продаж выбранного магазина.
    # @macro api_method
    # @macro seller_id
    # @macro geodependent
    # @macro paginated
    # @macro user_location
    # @macro returns_listing
    def seller_outlets seller_id, params
      listing "seller/#{seller_id}/outlets", params
    end

    # @!group Производители

    # Список производителей: получение списка производителей, товары которых представлены в каталоге моделей на Товарах@Mail.Ru
    # @option params [Integer] :category_id Идентификатор товарной категории, для которой нужно получить список производителей
    # @option params [Integer] :page (1) Номер страницы
    # @option params [Integer] :results_per_page (выводятся все результаты) Количество результатов на страницу (max: 30)
    # @macro returns_listing
    def vendors params=nil
      listing "vendor"
    end

    # Информация о производителе: получение информации о производителе.
    # @macro vendor_id
    # @macro returns_object
    def vendor vendor_id
      get "vendor/#{vendor_id}"
    end

    # @!group Геоинформация

    # Список регионов: получение списка регионов верхнего уровня.
    # @macro api_method
    # @macro paginated
    # @macro returns_listing
    def regions params=nil
      listing "regions", params
    end

    # Список дочерних регионов: получение списка дочерних регионов для выбранного региона.
    # @macro api_method
    # @macro region_id
    # @macro paginated
    # @macro returns_listing
    def region_children region_id, params=nil
      listing "region/#{region_id}/children", params
    end

    # Информация о регионе: получение информации о выбранном регионе.
    # @macro region_id
    # @macro returns_object
    def region region_id
      get "region/#{region_id}"
    end

    # Текстовый поиск региона: получение списка регионов, удовлетворяющих строке запроса.
    # @option params [String] :query Полное или частичное название региона (обязательно!)
    # @option params [Integer] :total (5) Количество результатов (max: 10)
    # @macro returns_object
    def region_suggest params
      get "region/suggest", params
    end

    # @!endgroup

  end

  extend Configuration
  extend Connection
  extend APIRequest
  extend APIMethods

end
