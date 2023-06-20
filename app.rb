# frozen_string_literal: true

require 'sinatra/base'
require 'logger'

# App is the main application where all your logic & routing will go
class App < Sinatra::Base
  set :erb, escape_html: true
  enable :sessions

  attr_reader :logger, :groups

  def initialize
    super
    @logger = Logger.new('log/app.log')
    @groups ||= begin
      groups_from_id =`id`.to_s.match(/groups=(.+)/)[1].split(',').map do |g|
        g.match(/\d+\((\w+)\)/)[1]
      end

      groups_from_id.select { |g| g.match?(/^P\w+/)}

    end
  end

  def title
    'Summer Institute-Blender'
  end

  def projects_root
    "#{__dir__}/projects"
  end

  def project_dirs
    Dir.children(projects_root).reject {|dir| dir == 'input_files'}.sort_by(&:to_s)
  end

  def input_files_dir
    "#{projects_root}/input_files"
  end

  def copy_upload(input: nil, output: nil)
  input_sha = Pathname.new(input).file? ? Digest::SHA256.file(input) : nil
  output_sha = Pathname.new(output).file? ? Digest::SHA256.file(outout) : nil
  return if input_sha.to_s == output_sha.to_s

  File.open(output, 'wb') do |f|
    f.write(input.read)
  end
end

def job_state(job_id)
  state = `/bin/squeue -j #{job_id} -h -o '%t'`.chomp
  s = {
    '' => 'Completed',
    'R' => 'Running',
    'C' => 'Completed',
    'Q' => 'Queued',
    'CF' => 'Queued',
    'PD' => 'Queued',
  }[state]

  s.nil? ? 'Unknown' : s
end

def badge(state)
  {
    '' => 'warning',
    'Unknown' => 'warning',
    'Running' => 'success',
    'Queued' => 'info',
    'Completed' => 'primary',
  }[state.to_s]
end




  get '/' do
    logger.info('requesting the index')
    @flash = session.delete(:flash) || { info: 'Welcome to Summer Institute!' }
    
    @project_dirs = project_dirs

    @all_projects = all_projects
    
    erb(:index)

  end

  def all_projects
    project_dirs.map do |dir|
      file = File.read("#{projects_root}/#{dir}/.info")
      file_hash = JSON.parse(file)
      {
        dir: dir,
        name: file_hash["name"]
      }
    end
    
  end

  get "/projects/:dir" do
    if params[:dir] == 'new' || params[:dir] == "input_files"
      erb(:new_project)
    else
      @dir = Pathname("#{projects_root}/#{params[:dir]}")
      @flash = session.delete(:flash)
      @uploaded_blend_files = Dir.glob("#{input_files_dir}/*.blend").map { |f| File.basename(f)} 
      file = File.read("#{@dir}/.info")
      file_hash = JSON.parse(file)
      @project_name = file_hash["name"]
      # @project_name = @dir.basename.to_s.gsub(" ", "_").capitalize
      
      
      unless @dir.directory? || @dir.readable?
        session[:flash] = {danger: "#{@dir} does not exist"}
        redirect(url("/"))
      end

      `touch #{@dir}/.video_render_job_id`
      `touch #{@dir}/.frame_render_job_id`

      @images = Dir.glob("#{@dir}/*.png")
      `touch #{@dir}/.frame_render_job_id`
      @frame_render_job_id = File.read("#{@dir}/.frame_render_job_id").chomp
      @frame_render_job_state = job_state(@frame_render_job_id)
      @frame_render_badge = badge(@frame_render_job_state)

      @video_render_job_id = File.read("#{@dir}/.video_render_job_id").chomp
      @video_render_job_state = job_state(@video_render_job_id)
      @video_render_badge = badge(@video_render_job_state)

      erb(:show_project)
    end
  end

  post "/projects/new" do
    logger.info("Trying to render frames with: #{params.inspect}")
    
    dir = rand(1..999999)
    
    project_info = {
      "name" => params[:name] ,
      "icon" => "camera"
    }
    
    full_dir = "#{projects_root}/#{dir}".tap{ |d| FileUtils.mkdir_p(d) }

    File.open("#{full_dir}/.info", "w") do |f|
      f.write(project_info.to_json)
    end

    session[:flash] = {info: "made new project '#{params[:name]}'"}
    redirect(url("/projects/#{dir}"))
  end
  
  post "/delete/:dir" do
    dir = params[:dir]
    file = File.read("#{projects_root}/#{dir}/.info")
    file_hash = JSON.parse(file)
    session[:flash] = {info: "Successfully deleted  '#{file_hash["name"]}'"}
    FileUtils.remove_dir("#{projects_root}/#{dir}", true)
    redirect(url("/"))
  end

  get "/edit/:dir" do

    if params[:dir] == "new" || params[:dir] == "input_files"
      erb(:new_project)
    else
      @dir = params[:dir]
      @flash = session.delete(:flash)
      @uploaded_blend_files = Dir.glob("#{input_files_dir}/*.blend").map { |f| File.basename(f)} 
      file = File.read("#{projects_root}/#{@dir}/.info")
      file_hash = JSON.parse(file)
      @project_name = file_hash["name"]
      @project_icon = file_hash["icon"]
      
      

      @path_dir = Pathname("#{projects_root}/#{@dir}")

      unless @path_dir.directory? || @path_dir.readable?
        session[:flash] = {danger: "#{@path_dir} does not exist"}
        redirect(url("/"))
      end

      

      erb(:edit_project)
    end
  end

  post "/save/:dir" do
    @dir = params[:dir]
    #read file, returns hash. update hash, save hash back into info
    file = File.read("#{projects_root}/#{@dir}/.info")
    file_hash = JSON.parse(file)
    file_hash["name"] = params[:rename]
    file_hash["icon"] = params[:new_icon]
    File.open("#{projects_root}/#{@dir}/.info", "w") do |f|
     f.write(file_hash.to_json)
    end

    session[:flash] = {info: "Sucessfully renamed '#{file_hash["name"]}'" }
    redirect(url("/"))

  
  end

  post "/render/frames" do
    logger.info("Trying to render frames with: #{params.inspect}")

    if params["blend_file"].nil?
      blend_file = "#{input_files_dir}/#{params[:uploaded_blend_file]}"
    else
      blend_file = "#{input_files_dir}/#{params["blend_file"][:filename]}"
      copy_upload(input: params["blend_file"][:tempfile], output: blend_file)
    end
    
    dir = params[:dir]
    basename = File.basename(blend_file, ".*")
    walltime = format("%02d:00:00", params[:num_hours])

    args = ["-J", "blender-#{basename}", '--parsable', '-A', params[:project_name]]
    args.concat ["--export", "BLEND_FILE_PATH=#{blend_file},OUTPUT_DIR=#{dir},FRAMES_RANGE=#{params[:frames_range]}"]
    args.concat ['-n', params[:num_cpus], '-t', walltime, '-M', 'pitzer']
    args.concat ['--output', "#{dir}/frame-render-%j.out"]
    output = `/bin/sbatch #{args.join(' ')}  #{__dir__}/frames.sh 2>&1`

    job_id = output.strip.split(';').first
    `echo #{job_id} > #{dir}/.frame_render_job_id`

    session[:flash] = { info: "submitted job #{job_id}" }
    redirect(url("/projects/#{dir.split('/').last}"))

    post '/render/video' do
      logger.info("Trying to render video with: #{params.inspect}")
  
      output_dir = params[:dir]
      frames_per_second = params[:frames_per_second]
      walltime = format('%02d:00:00', params[:num_hours])
  
      args = ['-J', 'blender-video', '--parsable', '-A', params[:project_name]]
      args.concat ['--export', "FRAMES_PER_SEC=#{frames_per_second},FRAMES_DIR=#{output_dir}"]
      args.concat ['-n', params[:num_cpus], '-t', walltime, '-M', 'pitzer']
      args.concat ['--output', "#{output_dir}/video-render-%j.out"]
      output = `/bin/sbatch #{args.join(' ')}  #{__dir__}/render_video.sh 2>&1`
  
      job_id = output.strip.split(';').first
      `echo #{job_id} > #{output_dir}/.video_render_job_id`
  
      session[:flash] = { info: "Submitted job #{job_id}"}
      redirect(url("/projects/#{output_dir.split('/').last}"))
    end
  end



end