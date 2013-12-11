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

    def get resource, params=nil
      response = super
      hash = decamelize_hash_keys response[response.keys.first]
      DeepOpenStruct.load hash
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
    def listing resource, params=nil
      Listing.new resource, params
    end

    ### Товарные категории

    ## Список категорий
    # Получение списка товарных категорий верхнего уровня.
    # Ресурс является геозависимым и в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона. Нет Да
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  выводятся все результаты  Нет
    def categories params
      listing "category", params
    end


    ## Список подкатегорий
    # Получение списка подкатегорий для товарной категории.
    # Ресурс является геозависимым и в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # type Строка  Фильтрация выходных данных по типу товарной категории: all | model | parameterized | general all Нет
    # page Число Номер страницы. 1 Нет
    # results_per_page Число Количество результатов на страницу. Максимальное значение: 30.  выводятся все результаты  Нет
    def category_children category_id, params
      listing "category/#{category_id}/children", params
    end

    ## Информация о категории
    # Получение информации о товарной категории.
    # Ресурс является геозависимым.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    def category category_id, params
      get "category/#{category_id}", params
    end

    ## Список параметров категории
    # Получение списка параметров товарной категории
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # parameter_set Строка  Тип набора параметров категории. popular | all popular Нет
    def category_parameters category_id, params=nil
      get "category/#{category_id}/parameters", params
    end

    ## Список моделей категории
    # Получение списка моделей в модельной товарной категории. Для обычных категорий ресурс возвращает ошибку.
    # Ресурс является геозависимым и в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # vendor_id Число Идентификатор производителя.    Нет
    # sort  Строка  Тип сортировки моделей. date - сортировка по новизне; popular - сортировка по популярности; price - сортировка по цене. popular Нет
    # sort_order  Строка  Направление сортировки. asc - по возрастанию desc - по убыванию desc  Нет
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  10  Нет
    def category_models category_id, params
      listing "category/#{category_id}/models", params
    end

    ## Список товарных предложений категории
    # Получение списка товарных предложений в обычной товарной категории. Для модельных и параметризированных категорий ресурс возвращает ошибку.
    # Ресурс является геозависимым и в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # category_id Число Идентификатор товарной категории.   Да
    # sort  Строка  Тип сортировки предложений. auction - по убыванию ставки; price - сортировка по цене. auction Нет
    # sort_order  Строка  Направление сортировки. asc - по возрастанию desc - по убыванию desc  Нет
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  10  Нет
    def category_offers category_id, params
      listing "category/#{category_id}/offers", params
    end

    ## Список хитов продаж категории
    # Получение списка 50 моделей - хитов продаж модельной товарной категории. Для обычных категорий ресурс возвращает ошибку.
    # Список отсортирован по степени убывания популярности у покупателей.
    # Ресурс является геозависимым.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    def category_hits category_id, params
      listing "category/#{category_id}/hits", params
    end

    # Список новинок категории
    # Получение списка моделей в модельной товарной категории. Для обычных категорий ресурс возвращает ошибку.
    # Ресурс является геозависимым и в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # sort  Строка  Тип сортировки моделей. popular - сортировка по популярности; price - сортировка по цене. popular Нет
    # sort_order  Строка  Направление сортировки. asc - по возрастанию desc - по убыванию desc  Нет
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  10  Нет
    def category_newmodels category_id, params
      listing "category/#{category_id}/newmodels", params
    end


    ### Модели товаров

    ## Информация о модели
    # Получение информации об указанной модели.
    # Ресурс является геозависимым.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число  Идентификатор региона  Да
    def model model_id, params
      get "model/#{model_id}", params
    end

    ## Список характеристик модели
    # Получение списка характеристик указанной модели.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # parameter_set  Строка  popular|all  popular  Нет
    def model_parameters model_id, params=nil
      get "model/#{model_id}/parameters", params
    end

    # Список предложений модели
    # Получение списка товарных предложений указанной модели.
    # Ресурс является геозависимым и в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # sort  Строка  Тип сортировки предложений.
    # price - по цене;
    # rating - по рейтингу магазина + цене;
    # range - по расстоянию до ближайшей точки продаж (при указании местоположения пользователя);
    # auction - по убыванию ставки.
    # auction Нет
    # sort_order  Строка  Направление сортировки. Задается только в том случае, если у параметра sort_order указано значение price.
    # asc - по возрастанию desc - по убыванию
    # если у параметра sort_order указано значение price, сортировка по возрастанию;
    # если у параметра sort_order указано значение rating, сортировка по убыванию;
    # если у параметра sort_order указано значение range, сортировка по возрастанию.
    # Нет
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу.
    # Максимальное значение: 30.  10  Нет
    # latitude  Число Широта точки нахождения пользователя.   Нет
    # longitude Число Долгота точки нахождения пользователя.    Нет
    def model_offers model_id, params
      listing "model/#{model_id}/offers", params
    end

    ## Список точек продаж модели
    # Получение списка точек продаж указанной модели.
    # Ресурс является геозависимым и в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  10  Нет
    # latitude  Число Широта точки нахождения пользователя.   Нет
    # longitude Число Долгота точки нахождения пользователя.    Нет
    def model_outlets model_id, params
      listing "model/#{model_id}/outlets", params
    end

    ### Товарные предложения

    ## Информация о товарном предложении
    # Получение расширенной информации об указанном товарном предложении магазина.
    def offer offer_id, params=nil
      get "offer/#{offer_id}", params
    end

    ### Поиск

    ## Полнотекстовый поиск
    # Получение списка моделей и товарных предложений, удовлетворяющих строке запроса.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # query Строка  Поисковый запрос.   Да
    # category_id Число Фильтрация результатов поиска по товарной категории.    Нет
    # seller_id Число Фильтрация результатов поиска по магазину.    Нет
    # price_min Число Фильтрация результатов поиска по минимальной цене товарных предложений.   Нет
    # price_max Число Фильтрация результатов поиска по максимальной цене товарных предложений.    Нет
    # sort  Строка  Тип сортировки результатов поиска. price - сортировка по возрастанию цены. relevance - по релевантности. relevance Нет
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  10  Нет
    def search params
      listing "search", params
    end

    ## Параметрический поиск
    # Получение списка моделей категории, удовлетворяющих набору заданных параметров.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # {parameter_id}  Строка  Параметр товарной категории.
    # В запросе вместо {parameter_id} указыватся id параметра. Список параметров и их id для определенной товарной категории можно получить с помощью ресурса "Список параметров категории".
    # Значение зависит от типа выбранного параметра категории:
    # тип параметра numeric - числовое значение {value} или числовой диапазон, значения границ которого разделяются запятой {min_value},{max_value};
    # тип параметра enum - список идентификаторов допустимых значений параметра, разделенный запятыми, {value1_id},{value2_id},{value3_id}, где {valueN_id} - идентификатор значения;
    # тип параметра bool - допустимые значения параметра: true и false. Нет
    # sort  Строка  Тип сортировки результатов поиска. date - по новизне; popular - популярности; price - по цене;  popular Нет
    # sort_order  Строка  Направление сортировки по цене. asc - по возрастанию desc - по убыванию desc  Нет
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  10  Нет
    def category_filter category_id, params
      listing "category/#{category_id}/filter", params
    end

    ### Отзывы

    ## Отзывы о магазине
    # Получение списка отзывов о магазине.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # sort  Строка  Тип сортировки отзывов. mark - по оценке пользователя; date - по дате добавления отзыва; valuable - по оценке полезности отзыва. date  Нет
    # sort_order  Строка  Направление сортировки. asc - по возрастанию desc - по убыванию desc  Нет
    # mark  Число Фильтрация отзывов по оценке магазина. Возможные значения: 1 2 3 4 5 all - все значения all Нет
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  0 (выводятся все результаты)  Нет
    def seller_reviews seller_id, params
      listing "seller/#{seller_id}/reviews", params
    end

    ### Магазины

    ## Информация о магазине
    # Получение информации о выбранном магазине.
    def seller seller_id
      get "seller/#{seller_id}"
    end

    ## Список точек продаж магазина
    # Получение списка точек продаж выбранного магазина.
    # Ресурс является геозависимым и в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # geo_id  Число Идентификатор региона.    Да
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  10  Нет
    # latitude  Число Широта точки нахождения пользователя.   Нет
    # longitude Число Долгота точки нахождения пользователя.    Нет
    def seller_outlets seller_id, params
      listing "seller/#{seller_id}/outlets", params
    end

    ### Производители

    ## Список производителей
    # Получение списка производителей, товары которых представлены в каталоге моделей на Товарах@Mail.Ru
    # Ресурс в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # category_id Число Идентификатор товарной категории, для которой нужно получить список производителей.   Нет
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу.
    # Максимальное значение: 30.  0 (выводятся все результаты)  Нет
    def vendors
      listing "vendor"
    end

    ## Информация о производителе
    # Получение информации о производителе.
    def vendor vendor_id, params=nil
      get "vendor/#{vendor_id}"
    end

    ### Геоинформация

    ## Список регионов
    # Получение списка регионов верхнего уровня.
    # Ресурс в ответе возвращает листинг.
    # Входные параметры:
    # Параметр / Тип / Описание / Значение по умолчанию / Обязательный
    # page  Число Номер страницы. 1 Нет
    # results_per_page  Число Количество результатов на страницу. Максимальное значение: 30.  10  Нет
    def regions params=nil
      listing "regions", params
    end

    ## Список дочерних регионов
    # Получение списка дочерних регионов для выбранного региона.
    # Ресурс в ответе возвращает листинг.
    def region_children region_id, params=nil
      listing "region/#{region_id}/children", params
    end

    ## Информация о регионе
    # Получение информации о выбранном регионе.
    # Ошибка в документации: Ресурс в ответе НЕ возвращает листинг.
    def region region_id
      get "region/#{region_id}"
    end

    ## Текстовый поиск региона
    # Получение списка регионов, удовлетворяющих строке запроса.
    # Ошибка в документации: Ресурс в ответе НЕ возвращает листинг.
    def region_suggest params
      get "region/suggest", params
    end

  end

  extend Configuration
  extend Connection
  extend APIRequest
  extend APIMethods

end
