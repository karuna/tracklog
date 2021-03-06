# encoding: utf-8

class LogsController < ApplicationController
  before_filter :authenticate
  before_filter :find_log_and_check_permission, :except => [:index, :tagged, :new, :create]

  require 'pp'

  def index
    @selected_year = params[:year] ? params[:year].to_i : Time.now.year

    @available_years = current_user
      .tracks
      .select("tracks.start_time")
      .order("tracks.start_time ASC")
      .map { |track| track.start_time.year }
      .uniq

    @logs = current_user
      .logs
      .select("logs.*, tracks.start_time")
      .joins(:tracks)
      .where("tracks.start_time >= ?", Time.mktime(@selected_year, 1, 1))
      .where("tracks.start_time < ?", Time.mktime(@selected_year + 1, 1, 1))
      .order("tracks.start_time ASC")
      .all
      .uniq

    calculate_list
  end

  def tagged
    @logs = current_user.logs
      .select("logs.*, tracks.start_time")
      .joins(:tracks)
      .joins(:tags)
      .where("tags.name = ?", params[:tag])
      .order("tracks.start_time ASC")
      .all
      .uniq

    calculate_list
  end

  def show
    departure_lat = @log.tracks.first.trackpoints.first.latitude
    departure_lng = @log.tracks.first.trackpoints.first.longitude
    # departure_result = Nokogiri.XML(open("http://aviationweather.gov/adds/dataserver_current/httpparam?dataSource=stations&requestType=retrieve&format=xml&radialDistance=5;#{departure_lng},#{departure_lat}").read)
    # @departure_airport = departure_result.search('station_id').text + ' (' + departure_result.search('site').text + ')'
    # departure_result = Nokogiri.XML(open("https://api.flightstats.com/flex/airports/rest/v1/xml/withinRadius/#{departure_lng}/#{departure_lat}/5?appId=058b0ced&appKey=5476fe6ce864d93d2623004c2a9daaab").read)
    # @departure_airport = departure_result.search('faa').text + ' (' + departure_result.search('name').text + ')'

    arrival_lat = @log.tracks.first.trackpoints.last.latitude
    arrival_lng = @log.tracks.first.trackpoints.last.longitude
    # arrival_result = Nokogiri.XML(open("https://api.flightstats.com/flex/airports/rest/v1/xml/withinRadius/#{arrival_lng}/#{arrival_lat}/5?appId=058b0ced&appKey=5476fe6ce864d93d2623004c2a9daaab").read)
    # @arrival_airport = arrival_result.search('faa').text + ' (' + arrival_result.search('name').text + ')'

    fusion_table_url = "https://www.googleapis.com/fusiontables/v1/query"
    fusion_table_id = "1ZyiBtjwgNxApITFl3VpOC4f-3N4h8cxG_e0l6PEU"
    api_key = "AIzaSyAm9yWCV7JPCTHCJut8whOjARd7pwROFDQ"

    @departure_json = JSON.parse(open("#{fusion_table_url}?sql=SELECT%20*%20FROM%20#{fusion_table_id}%20ORDER%20BY%20ST_DISTANCE(latitude_deg,%20LATLNG(#{departure_lat},#{departure_lng}))%20LIMIT%201&key=#{api_key}").read)
    @departure_airport = "#{@departure_json["rows"][0][1]} (#{@departure_json["rows"][0][3]})"

    @arrival_json = JSON.parse(open("#{fusion_table_url}?sql=SELECT%20*%20FROM%20#{fusion_table_id}%20ORDER%20BY%20ST_DISTANCE(latitude_deg,%20LATLNG(#{arrival_lat},#{arrival_lng}))%20LIMIT%201&key=#{api_key}").read)
    @arrival_airport = "#{@arrival_json["rows"][0][1]} (#{@arrival_json["rows"][0][3]})"



    respond_to do |format|
      format.html

      format.json do
        render :json => @log.tracks.map { |track|
          {
            :name => track.display_name,
            :points => track.trackpoints.map { |trackpoint|
              {
                :latitude  => trackpoint.latitude,
                :longitude => trackpoint.longitude,
                :elevation => trackpoint.elevation,
                :timestamp => trackpoint.time.to_i,
                :time      => trackpoint.time.strftime("%d.%m.%Y %H:%M")
              }
            }
          }
        }
      end

      format.gpx do
        filename = "log-#{@log.id}-#{@log.name.parameterize}.gpx"
        headers["Content-Disposition"] = %{Content-Disposition: attachment; filename="#{filename}"}
      end
    end
  end

  def tracks
    respond_to do |format|
      format.json do
        render :json => {
          :distance_units => current_user.distance_units,
          :tracks => @log.tracks.map { |track|
            track.trackpoints.map do |trackpoint|
              {
                :latitude  => trackpoint.latitude,
                :longitude => trackpoint.longitude,
                :elevation => trackpoint.elevation,
                :timestamp => trackpoint.time.to_i,
                :time      => trackpoint.time.strftime("%d.%m.%Y %H:%M")
              }
            end
          }
        }
      end
    end
  end

  def new
    @log = Log.new
  end

  def create
    @log = Log.new(log_params)
    @log.user = current_user

    unless @log.save
      render :action => :new and return
    end

    if track_file = log_params[:track_file]
      @log.create_tracks_from_gpx(track_file.read)
    end

    redirect_to @log
  end

  def edit
    @orig_log = @log.dup
  end

  def update
    @orig_log = @log.dup

    if @log.update_attributes(log_params)
      redirect_to @log
    else
      flash[:error] = "There was an error updating the log."
      render :edit
    end
  end

  def destroy
    @log.destroy
    redirect_to @log
  end

  def find_log_and_check_permission
    @log = Log.find(params[:id])

    unless @log.user_id == current_user.id
      flash[:error] = "You don’t have permission to view this log."
      redirect_to dashboard_path and return
    end
  end
  private :find_log_and_check_permission

  def calculate_list
    @total_distance = 0.0
    @total_duration = 0.0
    @logs_by_months = {}

    @logs.each do |log|
      @total_distance += log.distance
      @total_duration += log.duration

      time = Time.mktime(log.start_time.year, log.start_time.month, 1)

      @logs_by_months[time] ||= {
        :logs => [],
        :total_distance => 0.0,
        :total_duration => 0.0
      }

      @logs_by_months[time][:logs] << log
      @logs_by_months[time][:total_distance] += log.distance
      @logs_by_months[time][:total_duration] += log.duration
    end
  end
  private :calculate_list

  def log_params
    params.require(:log).permit(:name, :comment, :tags_list, :track_file)
  end
  private :log_params
end
