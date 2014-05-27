gulp            = require 'gulp'
gutil           = require 'gulp-util'
_               = require 'lodash'
changeCase      = require 'change-case'
Q               = require 'q'

fs              = require 'fs'
exec            = require('child_process').exec
mkdirp          = require 'mkdirp'
path            = require 'path'
async           = require 'async'
glob            = require 'glob'

connect         = require 'connect'

Feed            = require 'feed'
Post            = require './post'

plugins = (require 'gulp-load-plugins')()

config = _.defaults gutil.env,
    port: 7000 # on which port the server will be listening
    env: if gutil.env.production then 'production' else 'development'
    styles: []
    scripts: []
    icons: []
    html: { }
    blog: { }
    postsPerPage: 10
    src:
        icons: 'icons/*.png'
        manifest: 'manifest.coffee'
        less: 'styles/main.less'
        fonts: 'styles/fonts/*'
        jade: ['index.jade', 'views/*.jade']
        coffee: ['scripts/main.coffee']
        js: 'scripts/*.js'
        markdown: '*.md'
        images: '**/*.{png,jpg,webp,gif}'
        config: 'config.coffee'
    watch:
        coffee: ['scripts/**/*.coffee']
        less: ['styles/**/*.{less,css}']
        jade: ['*.jade', '*/**/*.jade']

if config.env isnt 'production'
    config = _.defaults config,
        lint: yes
        sourceMaps: yes

config.dest = "dist/#{config.env}"

try
    mkdirp.sync "#{config.dest}/content"

minifyJSON = ->
    plugins.tap (file) ->
        json = JSON.parse file.contents.toString()
        file.contents = new Buffer JSON.stringify json
        file

gulp.task 'watch', ->
    # server = livereload();
    gulp.watch config.src.manifest, cwd: 'src', ['manifest']
    gulp.watch [config.watch.coffee, config.src.js], cwd: 'src', ['scripts', 'styles', 'html']
    gulp.watch config.watch.jade, cwd: 'src', ['styles', 'html']
    gulp.watch [config.watch.less, config.src.fonts], cwd: 'src', ['styles']
    gulp.watch config.src.images, cwd: 'images', ['images']
    gulp.watch config.src.markdown, cwd: 'posts', ['content']
    gulp.watch config.src.config, cwd: 'src', ['config']

gulp.task 'clean', ->
    gulp.src ['**/*', '!.gitignore'], cwd: config.dest
    .pipe plugins.clean()

gulp.task 'less', ->
    gulp.src config.src.less, cwd: 'src'
    .pipe plugins.less paths: ['.', '../../node_modules']
    .pipe (if config.env is 'production' then plugins.minifyCss(noAdvanced: yes) else gutil.noop())
    .pipe plugins.autoprefixer cascade: true
    .pipe gulp.dest "#{config.dest}/styles"

gulp.task 'fonts', ->
    gulp.src config.src.fonts, cwd: 'src'
    .pipe gulp.dest "#{config.dest}/styles/fonts"

gulp.task 'jade', ['scripts', 'styles'], ->
    gulp.src config.src.jade, cwd: 'src', base: 'src'
    .pipe plugins.jade
        pretty: if config.env is 'production' then no else yes
        locals:
            _.extend config.blog, {
                styles: [
                    'styles/main.css'
                ]
                scripts: ['scripts/main.js']
                icons: []
            }
    .pipe gulp.dest "#{config.dest}"

gulp.task 'lint', ->
    if config.lint
        gulp.src config.src.coffee, cwd: 'src'
        .pipe (plugins.coffeelint())
        .pipe (plugins.coffeelint.reporter())

gulp.task 'coffee', ['lint'], ->
    gulp.src config.src.coffee, cwd: 'src', read: no
    .pipe plugins.browserify
        transform: ['coffeeify']
        extensions: ['.coffee']
    .pipe plugins.rename (file) ->
        file.extname = '.js'
        file
    # .pipe (if config.env is 'production' then plugins.uglify() else gutil.noop())
    .pipe gulp.dest "#{config.dest}/scripts"

gulp.task 'scripts', ['coffee']
gulp.task 'styles', ['less', 'fonts']
gulp.task 'html', ['jade']

gulp.task 'avatar', ['config'], ->
    gulp.src config.blog.image, cwd: 'src'
    .pipe gulp.dest config.dest

gulp.task 'images', ['avatar'], ->
    gulp.src config.src.images, cwd: 'images'
    .pipe plugins.using()
    .pipe gulp.dest "#{config.dest}/content/images"

gulp.task 'markdown', ['json'], ->
    html = ->
        plugins.tap (file) ->
            input = path.basename file.path
            output = config.html[input]
            file.contents = new Buffer output
            file

    gulp.src config.src.markdown, cwd: 'posts'
    .pipe html()
    .pipe plugins.rename (file) ->
        file.extname = '.html'
        file
    .pipe gulp.dest "#{config.dest}/content"

gulp.task 'json', (done) ->
    posts = []
    gulp.src config.src.markdown, cwd: 'posts'
    .pipe plugins.tap (file) ->
        post = new Post(file)

        posts.push _.omit post, 'html'

        config.html[path.basename file.path] = post.html

        gutil.log gutil.colors.cyan "Processed #{post.id}"
    .on 'end', ->
        posts = _.sortBy posts, 'date'
        posts.reverse()
        files = []
        for post, i in posts by config.postsPerPage
            files.push posts[i...i + config.postsPerPage].map (post) ->
                post.page = i + 1
                post

        config.posts = _.flatten posts
        gutil.log gutil.colors.green "Finished processing #{posts.length} posts in #{files.length} pages"
        j = 0
        async.each files, (file, done) ->
            j++
            config.blog.pages = files.length
            fs.writeFile "#{config.dest}/content/posts.#{j}.json",
                JSON.stringify(file), done
        , done
    null # We do not want to return the stream

gulp.task 'rss', ['config', 'json'], (done) ->
    process = (post) ->
        post.link = "#{config.blog.link}/#!/#{post.page}/#{post.id}"
        post.author = config.blog.author
        post

    feed = new Feed(_.extend config.blog)
    feed.addItem process post for post in config.posts

    xml = feed.render 'atom-1.0'
    fs.writeFile "#{config.dest}/rss.xml", xml, done


gulp.task 'content', ['markdown', 'json', 'images', 'rss']

gulp.task 'config', ['json'], ->
    gulp.src config.src.config, cwd: 'src'
    .pipe plugins.cson()
    .pipe plugins.jsonEditor (json) ->
        if config.env isnt 'production'
            json.link = "http://localhost:#{config.port}"
            json.rss = "http://localhost:#{config.port}/rss.xml"
        json = _.extend json, config.blog || {}
        config.blog = json
        json
    .pipe (if config.env is 'production' then minifyJSON() else gutil.noop())
    .pipe gulp.dest config.dest

gulp.task 'build', ['content', 'html', 'config']
gulp.task 'default', ['build']

gulp.task 'publish', ['build'], (done) ->
    # run the script `./publish.sh`
    if config.env isnt 'production'
        throw new Error 'You can only publish production builds. Use the --production flag with this task.'

    cmd = "./publish.sh '#{config.blog.github.username}' '#{config.dest}'"
    gutil.log gutil.colors.cyan "Executing command #{cmd}..."
    exec cmd, (err, stdout, stderr) ->
        gutil.log stdout
        gutil.log stderr
        done err

gulp.task 'serve', ->
    server = connect.createServer()
    server.use '/', connect.static "#{__dirname}/#{config.dest}"
    server.use '/', connect.static "#{__dirname}/src" if config.env isnt 'production'
    server.listen config.port, ->
        gutil.log "Server listening on port #{config.port}"