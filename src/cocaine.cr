require "http/server"
# Locally Import
# require "./param"

module Cocaine
  VERSION = "0.1.0"

  struct Context
    getter context : HTTP::Server::Context
    getter method : Pointer(UInt8)
    getter method_size : Int32
    getter path : Pointer(UInt8)
    getter path_size : Int32

    def initialize(@context : HTTP::Server::Context)
      @method = @context.request.method.to_unsafe
      @method_size = @context.request.method.size
      @path = @context.request.path.to_unsafe
      @path_size = @context.request.path.size
    end
  end
end

macro cocaine_generate_endpoint(descriptions)
  module Cocaine
    ############################################################################
    # Macro
    ############################################################################

    # TODO: Add a check for descriptions

    # INFO: Collect every methods possible
    #-----
    {% methods = [] of String %}
    {% for description in descriptions %}
      {% for key in description["methods"] %}
        {% methods << key %}
      {% end %}
    {% end %}
    {% methods = methods.uniq %}
    #-----

    # INFO: Sort Methods by Size
    {% methodsBySize = {} of UInt32 => Array[String] %}
    {% sizes = [] of UInt32 %}
    {% for method in methods %}
      {% sizes << method.size %}
    {% end %}
    {% sizes = sizes.uniq %}
    {% sizes = sizes.sort %}
    {% for size in sizes %}
      {% methodsBySize[size] = [] of String %}
    {% end %}
    {% for method in methods %}
      {% methodsBySize[method.size] << method %}
    {% end %}

    # INFO: associates each path with a method
    #-----
    {% methodPaths = {} of String => Array(String) %}
    {% for method in methods %}
      {% methodPaths[method] = [] of String %}
    {% end %}
    {% for description in descriptions %}
      {% for method in description["methods"] %}
        {% methodPaths[method] << description["path"] %}
      {% end %}
    {% end %}
    #-----

    # INFO: Pre-analyze the path to know the indexes where the parameters are located
    #-----
    {% pathParamsIndexs = {} of String => Hash(String, Array(Int32)) %}
    {% for method in methods %}
      {% pathParamsIndexs[method] = {} of String => Array(Int32) %}
    {% end %}
    {% for description in descriptions %}
      {% for method in description["methods"] %}
        {% path = description["path"] %}
        {% pathParamsIndexs[method][path] = [] of Int32 %}
        {% onColon = false %}
        {% prevIndex = 0 %}
        {% for index in (0..path.size) %}
          {% if path[index..index] == ":" && onColon == false %}
            {% pathParamsIndexs[method][path] << (index - prevIndex) %}
            {% onColon = true %}
            {% prevIndex = index %}
          {% elsif path[index..index] == "/" && onColon == true %}
            {% pathParamsIndexs[method][path] << (index - prevIndex) %}
            {% onColon = false %}
            {% prevIndex = index %}
          {% elsif index + 1 == path.size && onColon == true %}
            {% pathParamsIndexs[method][path] << (index - prevIndex) %}
            {% prevIndex = index %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
    #-----

    {% puts pathParamsIndexs %}

    ############################################################################
    # Private Function
    ############################################################################

    ############################################################################
    # Main Function
    ############################################################################

    @[AlwaysInline]
    def self.match_endpoint(context : Context)
      case context.method_size
      {% for key in methodsBySize %}
        when {{ key.id }}
          case context.method
          {% for method in methodsBySize[key] %}
            when .memcmp {{ method }}.to_unsafe, {{ key.id }}
              path = uninitialized Pointer(UInt8)
              pathSize = uninitialized Int32
              pathRef = uninitialized Pointer(UInt8)
              pathRefSize = uninitialized Int32
              pathIndex = uninitialized Int32
              itr = uninitialized Int32

              path = context.path
              
              pathSize = context.path_size
              {% for path, index in methodPaths[method] %}
                puts ">>>>>>>>>>. NEW PATH"
                # INFO: Path Matching

                tmpPath = path

                pathRef = {{ path }}.to_unsafe
                tmpPathRef = pathRef
                pathRefSize = {{ path }}.size
                pathIndex = 0
                paramsIndexs = StaticArray{{ pathParamsIndexs[method][path] }}
                index = 0
                itr = 0
                while itr < paramsIndexs.size
                  puts "New Loop"
                  puts "tmpPath: #{ String.new Bytes.new(tmpPath, paramsIndexs[itr]) } | tmpPathRef: #{ String.new Bytes.new(tmpPathRef, paramsIndexs[itr]) }"

                  unless tmpPath.memcmp(tmpPathRef, paramsIndexs[itr]) == 0
                    break
                  end




                  tmpPath += paramsIndexs[itr]
                  while tmpPath.value != 47 && index < pathSize
                    # puts "test"
                    tmpPath += 1
                    index += 1
                  end

                  # puts "---------------"

                  itr += 2
                  if itr == paramsIndexs.size
                    if (index == pathSize)
                      puts "FOUND !!!!!!!!!!!!!!!!!!"
                      return
                    end
                    break
                  end

                  tmpPathRef += paramsIndexs[itr]
                  puts "tmpPathRef: #{ String.new Bytes.new(tmpPathRef, paramsIndexs[itr + 1]) }"

                  tmpPathRef += paramsIndexs[itr + 1]


                end
              {% end %}
          {% end %}
          end
      {% end %}
      end
    end
  end
end

################################################################################
#
################################################################################

def fun_get
  puts "fun_get"
end

def fun_post
  puts "fun_post"
end

def fun_delete
  puts "fun_delete"
end

def fun_patch
  puts "fun_patch"
end

def fun_put
  puts "fun_put"
end

cocaine_generate_endpoint [
  {
    "cors" => true,
    "methods" => {
      "GET" => fun_get,
      "POST" => fun_post,
      "DELETE" => fun_delete,
      "PATCH" => fun_patch,
      "PUT" => fun_put
    },
    "name" => "Test", # Name for the struct exemple PosTest
    "path" => "/user/:id" # /user & /user/ it's exactly the same
  },
  {
    "cors" => true,
    "methods" => {
      "GET" => fun_get,
      "POST" => fun_post,
      "DELETE" => fun_delete,
      "PATCH" => fun_patch,
      "PUT" => fun_put
    },
    "name" => "Test", # Name for the struct exemple PosTest
    "path" => "/user/:id/:oo" # /user & /user/ it's exactly the same
  }
]

puts "------>"
server = HTTP::Server.new do |context|
  ctx = Cocaine::Context.new context
  start = Time.monotonic
  Cocaine.match_endpoint ctx
  elapsed = Time.monotonic - start
  puts "> #{ elapsed.nanoseconds } ns ; #{ 1_000_000_000_f32 / elapsed.nanoseconds }"
end
server.listen "0.0.0.0", 5000
