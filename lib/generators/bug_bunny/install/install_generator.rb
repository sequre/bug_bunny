# frozen_string_literal: true

require 'rails/generators'

module BugBunny
  module Generators
    # Generador de instalación estándar de Rails para BugBunny.
    #
    # Este generador se encarga de realizar el "scaffolding" inicial necesario para
    # integrar la gema en una aplicación Rails existente.
    #
    # Acciones principales:
    # 1. Crea el archivo de configuración (Initializer).
    # 2. Establece la estructura de directorios para los controladores AMQP.
    #
    # @example Ejecución desde la terminal
    #   rails generate bug_bunny:install
    class InstallGenerator < Rails::Generators::Base
      # Define la raíz de los recursos para buscar las plantillas (templates).
      # @api private
      source_root File.expand_path('templates', __dir__)

      desc 'Instala la configuración inicial de BugBunny y crea la estructura de directorios.'

      # Genera el archivo de configuración inicial.
      # Copia la plantilla `initializer.rb` a `config/initializers/bug_bunny.rb` en la app destino.
      #
      # @return [void]
      def create_initializer
        template 'initializer.rb', 'config/initializers/bug_bunny.rb'
      end

      # Crea la estructura de carpetas necesaria para el patrón MVC de BugBunny.
      #
      # Genera:
      # * `app/bug_bunny/controllers/`: Directorio donde vivirán los controladores de consumidores.
      # * `.keep`: Archivo marcador para asegurar que Git rastree la carpeta aunque esté vacía.
      #
      # @return [void]
      def create_directories
        empty_directory 'app/bug_bunny/controllers'
        create_file 'app/bug_bunny/controllers/.keep', ''
      end
    end
  end
end
