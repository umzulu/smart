# encoding: utf-8
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  layout "smart_application"

  before_filter :require_login, :session_handler

  around_filter :catch_exceptions

  helper_method :current_user, :user_menu_ids, :user_systems, :user_group_settings

  #只有用户登录后, 才有权限访问页面
  def require_login
    if current_user.nil?
      redirect_to '/login'
    end
  end

  # 获取当前登录session
  def current_user_session
    @current_user_session ||= UserSession.find
  end

  # 获取当前用户
  def current_user
    @current_user ||= current_user_session && current_user_session.record
  end

  def ajax_request?
    request.xhr?
  end

  #  用于判断是否为json请求，一般用于index请求时，决定是否需要查询列表数据
  def json_request?
    request.format.symbol == :json
  end

  # 判断是否为html请求
  def html_request?
    request.format.symbol == :html
  end

  # 判断请求方法是否为get方式
  def get_request?
    request.method == 'GET'
  end

  # 判断请求方法是否为post方式
  def post_request?
    request.method == 'POST'
  end

  def session_handler
    Thread.current[:current_user] = current_user
    # 如果是get请求并且是html请求，且不是ajax请求，则更新session中的菜单
    if get_request? && html_request? && !ajax_request?
      update_session_menus
    end
  end

  # 更新session中的用户的菜单
  def update_session_menus
    current_menu = Menu.where("controller = ? and action = ? and menu_type = 'LEAF'", params[:controller], params[:action]).first
    if current_menu
      session[:curr_leaf_menu] = current_menu
      session[:curr_group_menu] = current_menu.group_menu
      session[:curr_module_menu] = current_menu.module_menu
      session[:curr_system] =  current_menu.system
    else
      logger.debug '当前菜单不存在'
    end
  end

  # 用户的菜单ids
  def user_menu_ids
    session[:user_menu_ids] ||= current_user.menu_ids
  end

  # 用户的系统（菜单）
  def user_systems
    session[:user_systems] ||= current_user.systems(user_menu_ids)
  end

  # 用户的所有权限json,访问home/index时运行
  def user_group_settings
    current_user.groups.to_json(
        only: [:name],
        include: {
            permissions: {only: [:code, :controller]},
            roles: {only: [:code, :name]}
        }
    )
  end

  # 异常处理
  def catch_exceptions
    #if json_request?
      begin
        yield
      rescue => e
        if e.is_a? CanCan::AccessDenied
          render json: { notice: '当前用户不允许此操作' } , status: 401
        elsif e.is_a? SmartStandardError
          render json: e.to_json, status: 500
        else
          render json: { notice: e.message }, status: 500
        end

        logger.debug '×' *160

        logger.debug "#{e.class}: #{ Time.now.strftime("%Y-%m-%d %H:%M:%S") } 访问[" + request.url + ']出错'

        e.backtrace.each { |item| logger.error item }

        logger.debug '×' *160
      end
    #else
    #  yield
    #end
  end

  private

  # Cancan::Ability增加参数:当前访问controller_path
  def current_ability
    @current_ability ||= SmartAbility.new(current_user, controller_path)
  end

end
