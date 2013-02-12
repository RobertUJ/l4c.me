# Module dependencies
_     = underscore     = require 'underscore'
_.str = underscore.str = require 'underscore.string'
_.mixin _.str.exports()

express       = require 'express'
fs            = require 'fs'
invoke        = require 'invoke'
moment        = require 'moment'
mongo_session = require('connect-mongo')(express)
mongoose      = require 'mongoose'
nodejs_url    = require 'url'
passport      = require 'passport'
spawn         = require('child_process').spawn
util          = require 'util'


# Initialize app
app            = express()
module.exports = app


# L4C library
config        = require '../config.json'
lib           = require './lib'
error_handler = lib.error_handler
helpers       = lib.helpers
middleware    = lib.middleware(app)
model         = require './models'
url_domain    = 'http://' + config.domain


# Route Params
app.param 'page', (req, res, next, id) ->
	if id.match /[0-9]+/
		req.param.page = parseInt req.param.page, 10
		next()
	else
		return error_handler(404)(req, res)


app.param 'size', (req, res, next, id) ->
	if id in ['p', 'm', 'g', 'o']
		next()
	else
		return next('route')


app.param 'slug', (req, res, next, id) ->
	if id not in ['editar']
		next()
	else
		return next('route')


app.param 'sort', (req, res, next, id) ->
	if id in ['ultimas', 'top']
		next()
	else
		return next('route')


app.param 'user', (req, res, next, id) ->

	model.user.findOne username: id, (err, user) ->
		return next('route') if err || user == null
		next()






# Routes

app.get '/500', (req, res) ->
	throw new Error('test')
	res.send ''

app.get '/', middleware.hmvc('/fotos/:sort?')


app.get '/fotos/:sort/pag/:page?', middleware.paged('/fotos/:sort?')
app.get '/fotos/ultimas', (req, res) -> res.redirect '/fotos', 301
app.get '/fotos/:sort?', (req, res, next) ->
	sort = req.param 'sort', 'ultimas'
	page = parseInt req.param('page', 1), 10
	per_page = config.pagination
	photos = null
	query = { $nor: [{ privacy: 'private'}] }

	if req.originalUrl == '/fotos'
		return res.redirect '/'

	invoke (data, callback) ->
		model.photo.count query, callback

	.and (data, callback) ->
		photos = model.photo
			.find(query)
			.limit(per_page)
			.skip(per_page * (page - 1))
			.populate('_user')

		photos.sort({ created_at: -1 })  if sort == 'ultimas'
		photos.sort({ views: -1, created_at: -1 })  if sort == 'top'
		photos.exec callback

	.rescue (err) ->
		next err  if err

	.end null, (data) ->
		count = data[0]
		photos = data[1]
		pages = Math.ceil count / per_page

		res.locals.body_class = "gallery #{sort}"
		res.locals.pages = pages
		res.locals.path = "/fotos/#{sort}"
		res.locals.page = page
		res.locals.photos = photos
		res.locals.sort = sort
		res.locals.total = count

		if req.originalUrl == '/'
			res.locals.document_title = config.info.title  if config.info.title
			res.locals.document_description = config.info.description  if config.info.description

		res.render 'gallery'

###
# TODO: Show list of users with his latest 6 photos
app.get '/fotos/galeria/pag/:page?', middleware.paged('/fotos/galeria')
app.get '/fotos/galeria', (req, res, next) ->
	sort = 'galeria'
	page = parseInt req.param('page', 1), 10
	per_page = config.pagination
	photos = null
	query = {}

	invoke (data, callback) ->
		model.photo.count query, callback

	.and (data, callback) ->
		model.photo
			.find(query)
			.sort({ created_at: -1 })
			.limit(per_page)
			.skip(per_page * (page - 1))
			.populate('_user')
			.exec callback

	.rescue (err) ->
		next err  if err

	.end null, (data) ->
		count = data[0]
		photos = data[1]

		res.locals.body_class = "gallery #{sort}"
		res.locals.pages = Math.ceil count / per_page
		res.locals.page = page
		res.locals.path = "/fotos/#{sort}"
		res.locals.photos = photos
		res.locals.sort = sort
		res.locals.total = count

		res.render 'gallery'
###

app.get '/feed/:user', (req, res) ->
	username = req.param 'user'
	feed = null
	photos = null
	user = null

	# find user
	invoke (data, callback) ->
		model.user.findOne { username: username }, (err, doc) ->
			return callback err  if err
			return error_handler(404)(req, res)  if doc == null || doc.username != username

			user = doc
			callback null, user

	# find photos
	.then (data, callback) ->
		model.photo
			.find(_user: user._id)
			.nor([{ privacy: 'private'}])
			.sort({ created_at: -1 })
			.limit(config.rss.limit)
			.exec callback

	# create rss feed
	.then (data, callback) ->
		photos = data

		rss = require 'rss'
		feed = new rss
			author: username
			description: "Fotos de #{username}"
			feed_url: "#{url_domain}/feed/#{username}"
			image_url: "#{url_domain}/favicon.ico"
			site_url: "#{url_domain}/#{username}"
			title: "#{helpers.heart} #{config.info.name} - Fotos de #{username}"

		callback null, feed

	# add feed items
	.then (data, callback) ->
		_.each photos, (photo) ->
			url = "#{url_domain}/#{username}/#{photo.slug}"

			body = if _.isEmpty(photo.description) then '' else helpers.markdown(photo.description)
			body += """
				<p><a href="#{url}"><img src="#{url_domain}/uploads/#{photo._id}_m.#{photo.image.ext}"></p>
			"""

			feed.item
				date: photo.created_at
				description: body
				guid: photo._id
				title: photo.name
				url: url

		callback null, feed

	# send xml
	.end null, (data) ->
		xml = feed.xml()
		res.set 'Content-Type', 'application.xml'
		res.send xml


app.get '/login', (req, res, next) ->
	qs = res.locals.query_vars
	req.session.auth_redirect = qs.r  if not _.isUndefined(qs.r)

	if (req.isAuthenticated())
		return res.redirect if qs.r then qs.r else '/' + req.user.username

	res.locals.failed = not _.isUndefined(res.locals.query_vars.failed)
	res.render 'login'

set_auth_redirect = (req, res, next) ->
	qs = res.locals.query_vars
	req.session.auth_redirect = qs.r  if not _.isUndefined(qs.r)
	next()

auth_redirect = (req, res, next) ->
	url = req.session.auth_redirect || '/' + req.user.username
	req.session.auth_redirect = null
	res.redirect url

app.post '/login', passport.authenticate('local', failureRedirect: '/login?failed'), auth_redirect

app.get '/login/facebook', set_auth_redirect, passport.authenticate('facebook', { scope: config.facebook.permissions })
app.get '/login/facebook/callback', passport.authenticate('facebook', failureRedirect: '/login'), auth_redirect

app.get '/login/facebook/remove', middleware.auth, (req, res, next) ->
	model.user.update({ _id: req.user._id }, { $unset: { facebook: 1} }, false, -> res.redirect('/profile'))


app.get '/login/twitter', set_auth_redirect, passport.authenticate('twitter')
app.get '/login/twitter/callback', passport.authenticate('twitter', failureRedirect: '/login'), auth_redirect

app.get '/login/twitter/remove', middleware.auth, (req, res, next) ->
	model.user.update({ _id: req.user._id }, { $unset: { twitter: 1} }, false, -> res.redirect('/profile'))

app.get '/userinfo', (req, res, next) ->
	res.json req.user


app.get '/logout', (req, res, next) ->
	req.logout()

	qs = res.locals.query_vars
	return res.redirect if qs.r then qs.r else '/'


app.get '/registro', (req, res, next) -> res.redirect '/register'
app.get '/register', (req, res, next) ->
	res.locals.body_class = 'register'

	res.render 'register'


app.post '/register', (req, res, next) ->
	d = req.body
	u = new model.user

	invoke (data, callback) ->
		# u.clab = d.clab  if d.clab_boolean == 'yes'
		u.email = d.email
		u.password = d.password
		u.username = d.username
		u.save (err) -> callback err

	.rescue (err) ->
		next err  if err

	.end null, (data) ->
		# passport.authenticate('local', successRedirect: '/profile', failureRedirect: '/register?failed')(req, res)


# Logged in user routes
app.post '/comment', (req, res, next) ->
	if !req.user
		ip_address = req.headers['x-forwarded-for'] ? req.connection.remoteAddress
		console.log "denied guest comment on photo.slug - #{ip_address} - #{req.body.photo}"
		return error_handler(403)(req, res)

	comment =
		body: req.body.comment
		guest: true
		user:
			email: req.body.email
			name: req.body.name

	if req.user
		delete comment.user
		comment._user = req.user._id
		comment.guest = false

	console.log "comment photo.slug: #{req.body.photo}"

	invoke (data, callback) ->
		model.photo.findOne({ slug: req.body.photo }, callback).populate('_user')

	.then (data, callback) ->
		if data.privacy == 'private'
			return callback new Error('You can\'t send comments to private photos')

		data.comments.push comment
		data.save callback

	.rescue (err) ->
		next err

	.end null, (photo) ->
		# return res.json photo
		res.redirect "/#{photo._user.username}/#{photo.slug}#c#{_.last(photo.comments)._id}"


app.delete '/comment', (req, res, next) ->
	if !req.user
		ip_address = req.headers['x-forwarded-for'] ? req.connection.remoteAddress
		console.log "denied guest comment on photo.slug - #{ip_address} - #{req.body.photo}"
		return error_handler(403)(req, res)

	comment_id = req.body.comment

	model.photo
		.findOne( 'comments._id': comment_id )
		.populate('_user')
		.exec (err, photo) ->
			return next err  if err
			return error_handler(404)(req, res)  if photo == null
			return error_handler(403)(req, res)  if req.user._id.toString() != photo._user._id.toString()  # comments can only be deleted by photo owners

			comment = _.find photo.comments, (p) -> p._id.toString() == comment_id
			photo.update
					$pull:
						comments:
							_id: comment._id
				,
					safe: true
				,
					(err, done) ->
						return next err  if err
						res.redirect "/#{photo._user.username}/#{photo.slug}#comments"


app.get '/fotos/publicar', middleware.auth, (req, res) ->
	res.locals.body_class = 'upload'

	res.render 'gallery_upload'


app.post '/fotos/publicar', middleware.auth, (req, res, next) ->
	user = req.user
	name = req.body.name
	description = req.body.description
	privacy = req.body.privacy

	file = req.files.file
	file_ext = helpers.image.extensions[file.type]
	file_path = ""

	photo = new model.photo

	queue = invoke (data, callback) ->
		photo.name = name
		photo.description = description  if description && description != ''
		photo.privacy = if privacy && privacy in ['public', 'private'] then privacy else 'public'
		photo.image.ext = file_ext
		photo._user = user._id
		photo.save (err) ->
			console.log "photo create - #{name}"
			callback err

	# image upload - move file from /tmp to /public/uploads
	# image manipulation - resize & crop images asynchronously
	.then (data, callback) ->
		photo.upload_photo file.path, (err) ->
			return callback err  if err
			photo.resize_photos callback

	.then (data, callback) ->
		photo.set_image_data callback

	# set photo slug
	queue.and (data, callback) ->
		photo.set_slug (photo_slug) ->
			console.log "photo set slug - #{photo_slug}"
			callback null, photo_slug

	# tweet photo
	queue.then (data, callback) ->
		if photo.privacy != 'private' && req.user.twitter and req.user.twitter.share
			script = fs.realpathSync __dirname + '/../scripts/twitter.js'
			proc = spawn 'node', [script, photo._id]

			# log output and errors
			logBuffer = (buffer) -> console.log buffer.toString()
			proc.stdout.on 'data', logBuffer
			proc.stderr.on 'data', logBuffer

			# exit process
			# proc.on 'exit', (code, signal) ->
			# 	callback()

		callback()

	# rescue
	.rescue (err) ->
		console.log "photo error"
		next err  if err

	# end
	.end null, (data) ->
		# redirect
		console.log "photo end - redirect"
		res.redirect "/#{user.username}/#{photo.slug}"


app.get '/profile', middleware.auth, (req, res) ->
	res.locals.body_class = 'profile'
	res.locals.user = req.user
	res.render 'profile'


app.put '/profile', middleware.auth, (req, res) ->
	has_update = false
	updated = {}

	# user & email
	updated.username = req.body.username  if req.user.username != req.body.username && has_update = true
	updated.email = req.body.email  if req.user.email != req.body.email && has_update = true

	# password
	if not _.isUndefined req.body['change-password']
		p = model.user.encrypt_password req.body.password
		updated.password = p  if req.user.password != p && has_update = true

	# twitter sharing
	if twitter = true
		new_twitter_share = not _.isUndefined(req.body.twitter_share)
		current_twitter_share = req.user.twitter.share  if _.isObject(req.user.twitter)

		if current_twitter_share
			if current_twitter_share != new_twitter_share
				has_update = true
				updated['twitter.share'] = new_twitter_share

		else if new_twitter_share
			has_update = true
			updated['twitter.share'] = new_twitter_share

	# update
	if has_update
		model.user.update({ _id: req.user._id }, { $set: updated }, false, -> res.redirect('/profile'))
	else
		res.redirect('/profile')


# app.get '/tweets', middleware.auth, (req, res) ->
# 	res.send "GET /tweets", 'Content-Type': 'text/plain'


app.get '/:user/:slug', (req, res, next) ->
	slug = req.param 'slug'
	username = req.param 'user'
	logged_user = res.locals.logged_user
	is_mine = logged_user && logged_user.username == username

	user = null
	photo = null
	myphotos = []
	morephotos = []

	invoke (data, callback) ->
		model.photo
			.findOne( slug: slug )
			.populate('_user')
			.populate('comments._user')
			.exec (err, data) ->
				return callback err  if err
				return error_handler(404)(req, res)  if data == null || data._user.username != username
				return error_handler(403)(req, res)  if data.privacy == 'private' && !is_mine  # private photos can only be viewed by owners

				user = data._user
				photo = data
				photo.views += 1
				photo.save callback

	# more user photos
	.then (data, callback) ->
		photos = model.photo
			.find( _user: user._id )
			.nor([{ _id: photo._id }])

		if !is_mine
			photos.nor([{privacy: 'private'}])

		photos
			.sort({ created_at: -1 })
			.limit(6)
			.exec callback

	# random photos
	.and (data, callback) ->
		model.photo
			.find()
			.ne('_user', photo._user._id)
			.or( helpers.random_query() )
			.nor([{ privacy: 'private' }])
			.limit(6)
			.populate('_user')
			.exec callback

	# prev / next photos from user
	.and (data, callback) ->
		# console.log 'photo', photo
		logged_username = if logged_user && logged_user.username then logged_user.username else null
		photo.prev_next(logged_username, callback)

	.rescue (err) ->
		next err

	.end null, (data) ->
		photo.prev  = data[2][0]
		photo.next  = data[2][1]
		description = if photo.description? then _(photo.description)
						.chain()
						.clean()       # remove whitespace and break lines
						.escapeHTML()  # escape all HTML tags
						.prune(150)    # fancier version of truncate, doesn't return cut-off words
						.value()

		res.locals.body_class = 'small-header user single' + if photo.image.panorama then ' panorama' else ''
		res.locals.document_description = if !_.isUndefined(description) then description else ''
		res.locals.document_image = "#{url_domain}/uploads/#{photo._id}_m.#{photo.image.ext}"
		res.locals.document_title = photo.name
		res.locals.document_url = "#{url_domain}/#{username}/#{photo.slug}"
		res.locals.photo = photo
		res.locals.photos =
				from_user: data[0]
				from_all: data[1]
		res.locals.slug = slug
		res.locals.user = user
		res.locals.username = user.username

		res.render 'gallery_single'


app.get '/:user/:slug/sizes/:size', (req, res) ->
	slug = req.param 'slug'
	username = req.param 'user'

	logged_user = res.locals.logged_user
	is_mine = logged_user && logged_user.username == username

	model.photo
		.findOne( slug: slug )
		.populate('_user')
		.exec (err, photo) ->
			return next err  if err
			return error_handler(404)(req, res)  if photo == null || photo._user.username != username
			return error_handler(403)(req, res)  if photo.privacy == 'private' && !is_mine  # private photos can only be viewed by owners

			photo.views += 1
			photo.save()

			description = if photo.description? then _(photo.description)
						.chain()
						.clean()       # remove whitespace and break lines
						.escapeHTML()  # escape all HTML tags
						.prune(150)    # fancier version of truncate, doesn't return cut-off words
						.value()

			res.locals.body_class = 'small-header  user sizes'
			res.locals.photo = photo
			res.locals.size = req.param 'size'
			res.locals.slug = slug
			res.locals.user = photo._user
			res.locals.username = username
			res.locals.document_description = if !_.isUndefined(description) then description else ''
			res.locals.document_image = "#{url_domain}/uploads/#{photo._id}_m.#{photo.image.ext}"
			res.locals.document_title = photo.name
			res.locals.document_url = "#{url_domain}/#{username}/#{photo.slug}"

			res.render 'gallery_sizes'


app.get '/:user/pag/:page?', middleware.paged('/:user')
app.get '/:user', (req, res, next) ->
	logged_user = res.locals.logged_user
	username = req.param 'user'
	is_profile = logged_user && logged_user.username == username
	per_page = config.pagination
	page = parseInt req.param('page', 1), 10
	user = null
	photos = null

	invoke (data, callback) ->
		model.user.findOne username: username, (err, user) -> callback err, user

	.then (data, callback) ->
		return error_handler(404)(req, res)  if (!data)
		user = data

		query = { _user: user._id }
		if !is_profile
			query['$nor'] = [{ privacy: 'private'}]

		model.photo.count query, callback

	.and (data, callback) ->
		photos = model.photo
			.find( _user: user._id )

		if !is_profile
			photos.nor([{ privacy: 'private'}])

		photos
			.limit(per_page)
			.skip(per_page * (page - 1))
			.sort({ created_at: -1 })
			.populate('_user')
			.exec callback

	.rescue (err) ->
		next err  if err

	.end user, (data) ->
		count = data[0]
		photos = data[1]

		res.locals.body_class = 'gallery user'
		res.locals.pages = Math.ceil count / per_page
		res.locals.page = page
		res.locals.path = "/#{user.username}"
		res.locals.photos = photos
		res.locals.sort = null
		res.locals.total = count
		res.locals.user = user
		res.locals.username = username

		res.render 'gallery'


app.get '/:user/:slug/editar', middleware.auth, (req, res) ->
	slug = req.param 'slug'
	username = req.param 'user'

	user = null
	photo = null

	invoke (data, callback) ->
		model.photo
			.findOne( slug: slug )
			.populate('_user')
			.exec (err, data) ->
				return callback err  if err
				return error_handler(404)(req, res)  if data == null || data._user.username != username
				return error_handler(403)(req, res)  if req.user.username != username

				user = data._user
				photo = data
				callback()

	.rescue (err) ->
		next err

	.end null, (data) ->
		res.locals.body_class = 'small-header user single-edit' + if photo.image.panorama then ' panorama' else ''
		res.locals.document_descrition = photo.description || ''
		res.locals.document_image = "#{url_domain}/uploads/#{photo._id}_m.#{photo.image.ext}"
		res.locals.document_title = photo.name
		res.locals.document_url = "#{url_domain}/#{username}/#{photo._id}/editar"
		res.locals.photo = photo
		res.locals.slug = slug
		res.locals.user = user
		res.locals.username = user.username

		res.render 'gallery_edit'


app.put '/:user/:slug', middleware.auth, (req, res) ->
	slug = req.param 'slug'
	username = req.param 'user'

	user = null
	photo = null

	has_update = false
	updated = {}

	invoke (data, callback) ->
		model.photo
			.findOne( slug: slug )
			.populate('_user')
			.exec (err, data) ->
				return callback err  if err
				return error_handler(404)(req, res)  if data == null || data._user.username != username
				return error_handler(403)(req, res)  if req.user.username != username

				user = data._user
				photo = data
				callback()

	.then (data, callback) ->
		# name & description
		photo.name = req.body.name  if photo.name != req.body.name && has_update = true
		photo.description = req.body.description  if photo.description != req.body.description && has_update = true
		photo.privacy = req.body.privacy  if photo.privacy != req.body.privacy && has_update = true
		callback()

	.rescue (err) ->
		res.json [user, slug, req.body]
		# url = "/#{username}/#{slug}/editar"
		# res.redirect(url)

	.end null, (data) ->
		url = "/#{username}/#{slug}"

		# update
		if has_update
			photo.save -> res.redirect url
		else
			res.redirect url


app.delete '/:user/:slug', middleware.auth, (req, res) ->
	# user = req.param 'user'
	# slug = req.param 'slug'
	# res.send "DELETE /#{user}/#{slug}", 'Content-Type': 'text/plain'

	slug = req.param 'slug'
	username = req.param 'user'

	user = null
	photo = null

	invoke (data, callback) ->
		model.photo
			.findOne( slug: slug )
			.populate('_user')
			.exec (err, data) ->
				return callback err  if err
				return error_handler(404)(req, res)  if data == null || data._user.username != username
				return error_handler(403)(req, res)  if req.user.username != username

				user = data._user
				photo = data
				callback()

	.then (data, callback) ->
		photo.remove callback

	.and (data, callback) ->
		queue = invoke()
		index = 0
		nodejs_path = require 'path'

		_.each helpers.image.sizes, (size, key) ->
			path = nodejs_path.normalize "#{__dirname}/../public/uploads/#{photo._id}_#{size.size}.#{photo.image.ext}"

			if !index
				queue = invoke (data, cb) ->
					console.log 'photo delete start', path
					fs.unlink path, (err) ->
						if err
							console.log 'photo delete error', path
							return cb err

						console.log 'photo delete end', path
						cb()
			else
				queue.and (data, cb) ->
					console.log 'photo delete start', path
					fs.unlink path, (err) ->
						if err
							console.log 'photo delete error', path
							return cb err

						console.log 'photo delete end', path
						cb()

			index++

		queue.rescue callback
		queue.end null, (data) -> callback(null, data)

	.rescue (err) ->
		next err

	.end null, (data) ->
		res.redirect "/#{user.username}", 301
