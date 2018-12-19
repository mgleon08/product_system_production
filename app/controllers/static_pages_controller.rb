class StaticPagesController < ApplicationController
  def home
    @products = Product.all
  end

  def help
  end
end
