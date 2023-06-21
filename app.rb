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
        name: file_hash["name"],
        icon: file_hash["icon"]
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

      erb(:edit_project2)
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

    session[:flash] = {info: "Sucessfully edited '#{file_hash["name"]}'" }
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
  end

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


  def all_icons
    [
      'barcode',
      'address-card',
      'adjust',
      'ambulance',
      'american-sign-language-interpreting',
      'anchor',
      'archive',
      'arrow-down',
      'arrow-left',
      'arrow-right',
      'arrow-up',
      'arrows-alt',
      'arrows-alt-h',
      'arrows-alt-v',
      'assistive-listening-systems',
      'asterisk',
      'at',
      'audio-description',
      'backward',
      'balance-scale',
      'ban',
      'band-aid',
      'barcode',
      'bars',
      'baseball-ball',
      'basketball-ball',
      'bath',
      'battery-empty',
      'battery-full',
      'battery-half',
      'battery-quarter',
      'battery-three-quarters',
      'bed',
      'beer',
      'bell',
      'bell-slash',
      'bicycle',
      'binoculars',
      'birthday-cake',
      'blender',
      'blind',
      'bold',
      'bolt',
      'bomb',
      'book',
      'book-open',
      'bookmark',
      'bowling-ball',
      'box',
      'box-open',
      'boxes',
      'braille',
      'briefcase',
      'briefcase-medical',
      'broadcast-tower',
      'broom',
      'bug',
      'building',
      'bullhorn',
      'bullseye',
      'burn',
      'bus',
      'calculator',
      'calendar',
      'calendar-alt',
      'calendar-check',
      'calendar-minus',
      'calendar-plus',
      'calendar-times',
      'camera',
      'camera-retro',
      'capsules',
      'car',
      'caret-down',
      'caret-left',
      'caret-right',
      'caret-square-down',
      'caret-square-left',
      'caret-square-right',
      'caret-square-up',
      'caret-up',
      'cart-arrow-down',
      'cart-plus',
      'certificate',
      'chalkboard',
      'chalkboard-teacher',
      'chart-area',
      'chart-bar',
      'chart-line',
      'chart-pie',
      'check',
      'check-circle',
      'check-square',
      'chess',
      'chess-bishop',
      'chess-board',
      'chess-king',
      'chess-knight',
      'chess-pawn',
      'chess-queen',
      'chess-rook',
      'chevron-down',
      'chevron-left',
      'chevron-right',
      'chevron-up',
      'child',
      'church',
      'circle',
      'circle-notch',
      'clipboard',
      'clipboard-check',
      'clipboard-list',
      'clock',
      'clone',
      'closed-captioning',
      'cloud',
      'cloud-download-alt',
      'cloud-upload-alt',
      'code',
      'code-branch',
      'coffee',
      'cog',
      'cogs',
      'coins',
      'columns',
      'comment',
      'comment-alt',
      'comment-dots',
      'comment-slash',
      'compact-disc',
      'compass',
      'compress',
      'copy',
      'copyright',
      'couch',
      'credit-card',
      'crosshairs',
      'crow',
      'crown',
      'cube',
      'cubes',
      'cut',
      'database',
      'deaf',
      'desktop',
      'diagnoses',
      'dice',
      'dice-five',
      'dice-four',
      'dice-one',
      'dice-six',
      'dice-three',
      'dice-two',
      'divide',
      'dna',
      'dollar-sign',
      'dolly',
      'dolly-flatbed',
      'donate',
      'door-closed',
      'door-open',
      'dot-circle',
      'dove',
      'download',
      'dumbbell',
      'edit',
      'eject',
      'ellipsis-h',
      'ellipsis-v',
      'envelope',
      'envelope-open',
      'envelope-square',
      'equals',
      'eraser',
      'euro-sign',
      'exchange-alt',
      'exclamation',
      'exclamation-circle',
      'exclamation-triangle',
      'expand',
      'expand-arrows-alt',
      'external-link-alt',
      'external-link-square-alt',
      'eye',
      'eye-dropper',
      'eye-slash',
      'fast-backward',
      'fast-forward',
      'fax',
      'feather',
      'female',
      'fighter-jet',
      'file',
      'file-alt',
      'file-archive',
      'file-audio',
      'file-code',
      'file-excel',
      'file-image',
      'file-medical',
      'file-medical-alt',
      'file-pdf',
      'file-powerpoint',
      'file-video',
      'file-word',
      'filter',
      'fire',
      'fire-extinguisher',
      'first-aid',
      'flag',
      'flag-checkered',
      'flask',
      'folder',
      'folder-open',
      'font',
      'football-ball',
      'forward',
      'frog',
      'frown',
      'futbol',
      'gamepad',
      'gas-pump',
      'gavel',
      'gem',
      'genderless',
      'gift',
      'glass-martini',
      'glasses',
      'globe',
      'golf-ball',
      'graduation-cap',
      'greater-than',
      'greater-than-equal',
      'h-square',
      'hand-holding',
      'hand-holding-heart',
      'hand-holding-usd',
      'hand-lizard',
      'hand-paper',
      'hand-peace',
      'hand-point-down',
      'hand-point-left',
      'hand-point-right',
      'hand-point-up',
      'hand-pointer',
      'hand-rock',
      'hand-scissors',
      'hands',
      'hands-helping',
      'handshake',
      'hashtag',
      'hdd',
      'heading',
      'headphones',
      'heart',
      'heartbeat',
      'helicopter',
      'history',
      'hockey-puck',
      'home',
      'hospital',
      'hospital-alt',
      'hospital-symbol',
      'hourglass',
      'hourglass-end',
      'hourglass-half',
      'hourglass-start',
      'i-cursor',
      'id-badge',
      'id-card',
      'id-card-alt',
      'image',
      'images',
      'inbox',
      'indent',
      'industry',
      'infinity',
      'info',
      'info-circle',
      'italic',
      'key',
      'keyboard',
      'kiwi-bird',
      'language',
      'laptop',
      'leaf',
      'lemon',
      'less-than',
      'less-than-equal',
      'level-down-alt',
      'level-up-alt',
      'life-ring',
      'lightbulb',
      'link',
      'list',
      'list-alt',
      'list-ol',
      'list-ul',
      'location-arrow',
      'lock',
      'lock-open',
      'long-arrow-alt-down',
      'long-arrow-alt-left',
      'long-arrow-alt-right',
      'long-arrow-alt-up',
      'low-vision',
      'magic',
      'magnet',
      'male',
      'map',
      'map-marker',
      'map-marker-alt',
      'map-pin',
      'map-signs',
      'mars',
      'mars-double',
      'mars-stroke',
      'mars-stroke-h',
      'mars-stroke-v',
      'medkit',
      'meh',
      'memory',
      'mercury',
      'microchip',
      'microphone',
      'microphone-alt',
      'microphone-alt-slash',
      'microphone-slash',
      'minus',
      'minus-circle',
      'mobile',
      'mobile-alt',
      'money-bill',
      'money-bill-alt',
      'money-bill-wave',
      'money-bill-wave-alt',
      'money-check',
      'money-check-alt',
      'moon',
      'motorcycle',
      'mouse-pointer',
      'music',
      'neuter',
      'newspaper',
      'not-equal',
      'notes-medical',
      'object-group',
      'object-ungroup',
      'outdent',
      'paint-brush',
      'palette',
      'pallet',
      'paper-plane',
      'paperclip',
      'parachute-box',
      'paragraph',
      'parking',
      'paste',
      'pause',
      'pause-circle',
      'paw',
      'pen-square',
      'pencil-alt',
      'people-carry',
      'percent',
      'percentage',
      'phone-slash',
      'phone-square',
      'phone-volume',
      'piggy-bank',
      'pills',
      'plane',
      'play',
      'play-circle',
      'plug',
      'plus',
      'plus-circle',
      'plus-square',
      'podcast',
      'poo',
      'portrait',
      'pound-sign',
      'power-off',
      'prescription-bottle',
      'prescription-bottle-alt',
      'print',
      'procedures',
      'project-diagram',
      'puzzle-piece',
      'qrcode',
      'question',
      'question-circle',
      'quidditch',
      'quote-left',
      'quote-right',
      'receipt',
      'recycle',
      'redo',
      'redo-alt',
      'registered',
      'reply',
      'reply-all',
      'retweet',
      'ribbon',
      'road',
      'robot',
      'rocket',
      'rss',
      'rss-square',
      'ruble-sign',
      'ruler',
      'ruler-combined',
      'ruler-horizontal',
      'ruler-vertical',
      'rupee-sign',
      'save',
      'school',
      'screwdriver',
      'search',
      'search-minus',
      'search-plus',
      'seedling',
      'server',
      'share',
      'share-alt',
      'share-alt-square',
      'share-square',
      'shekel-sign',
      'shield-alt',
      'ship',
      'shipping-fast',
      'shoe-prints',
      'shopping-bag',
      'shopping-basket',
      'shopping-cart',
      'shower',
      'sign',
      'sign-in-alt',
      'sign-language',
      'sign-out-alt',
      'signal',
      'sitemap',
      'skull',
      'sliders-h',
      'smile',
      'smoking',
      'smoking-ban',
      'snowflake',
      'sort',
      'sort-alpha-down',
      'sort-down',
      'sort-numeric-down',
      'sort-numeric-up',
      'sort-up',
      'space-shuttle',
      'spinner',
      'square',
      'square-full',
      'star',
      'star-half',
      'step-backward',
      'step-forward',
      'stethoscope',
      'sticky-note',
      'stop',
      'stop-circle',
      'stopwatch',
      'store',
      'store-alt',
      'stream',
      'street-view',
      'strikethrough',
      'subscript',
      'subway',
      'suitcase',
      'sun',
      'superscript',
      'sync',
      'sync-alt',
      'syringe',
      'table',
      'table-tennis',
      'tablet',
      'tablet-alt',
      'tablets',
      'tachometer-alt',
      'tag',
      'tags',
      'tape',
      'tasks',
      'taxi',
      'terminal',
      'text-height',
      'text-width',
      'thermometer',
      'thermometer-empty',
      'thermometer-full',
      'thermometer-half',
      'thermometer-quarter',
      'thermometer-three-quarters',
      'thumbs-down',
      'thumbs-up',
      'thumbtack',
      'ticket-alt',
      'times',
      'times-circle',
      'toggle-off',
      'toggle-on',
      'toolbox',
      'trademark',
      'train',
      'transgender',
      'transgender-alt',
      'trash',
      'trash-alt',
      'tree',
      'trophy',
      'truck',
      'truck-loading',
      'truck-moving',
      'tshirt',
      'tty',
      'tv',
      'umbrella',
      'underline',
      'undo',
      'undo-alt',
      'universal-access',
      'university',
      'unlink',
      'unlock',
      'unlock-alt',
      'upload',
      'user',
      'user-alt',
      'user-alt-slash',
      'user-astronaut',
      'user-check',
      'user-circle',
      'user-clock',
      'user-cog',
      'user-edit',
      'user-friends',
      'user-graduate',
      'user-lock',
      'user-md',
      'user-minus',
      'user-ninja',
      'user-plus',
      'user-secret',
      'user-shield',
      'user-slash',
      'user-tag',
      'user-tie',
      'user-times',
      'users',
      'users-cog',
      'utensil-spoon',
      'utensils',
      'venus',
      'venus-double',
      'vials',
      'video',
      'video-slash',
      'volleyball-ball',
      'volume-down',
      'volume-off',
      'volume-up',
      'walking',
      'wallet',
      'warehouse',
      'weight',
      'wheelchair',
      'wifi',
      'window-close',
      'window-maximize',
      'window-minimize',
      'window-restore',
      'wine-glass',
      'wrench',
      'yen-sign',
      'yin-yang'  
    ]
  end


end