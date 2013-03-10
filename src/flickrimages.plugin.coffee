# Export Plugin
module.exports = (BasePlugin) ->
	# Define Flickr Image Plugin
	class FlickrImagePlugin extends BasePlugin
		# Plugin name
		name: 'flickrimages'

		# Plugin config
		config:
			flickrImagesPath: 'flickr-images'
			flickrTag: 'docpad'
			defaultSize: 500

		# DocPad is ready now
		# Lets use this time to extend our file model
		renderBefore: (opts,next) ->
			# Prepare
			docpad = @docpad
			config = @config
			pathUtil = require('path')
			fsUtil = require('fs')
			flickr = require('flickr-with-uploads').Flickr
			balUtil = require('bal-util')
			
			env = process.env
			
			client = new flickr(env.flickrKey, env.flickrSecret, env.flickrOAToken, env.flickrOASecret)
			fsImages = []
			flickrImages = []
			{collection,templateData} = opts
			fsImages = new docpad.FilesCollection()
			
			# Fetch our configuration
			flickrImagesPath = config.flickrImagesPath

			uniqueFlickrTitle = {}
			
			endTask = () ->
				fsImages.forEach (document)->
					mImage
					flickrTitle = document.get('flickrTitle')

					for image in flickrImages
						if image.title == flickrTitle
							mImage = image
							break
					if mImage
						if mImage.mtime > document.stat.mtime/1000
							#console.log 'image is already up to date on flickr'
							document.set 'flickrURL' , mImage.url
							if mImage.sDefault
								document.set 'flickrImage',mImage.sDefault
								document.set 'flickrImageBig',mImage.big
							else
								document.set 'flickrImage',mImage.big
						else
							console.log 'error: should already be up to date'
					else
						console.log 'error: should already be on flickr'
				next()


			uploadTasks = new balUtil.Group(endTask)	

			handleOnePhoto = (photo, tasks) ->

				# check that the photo online is not duplicate
				if uniqueFlickrTitle[photo.title]
					docpad.log 'warn', 'This image is available more than once on flickr with the same title:' + photo.title
					return
				uniqueFlickrTitle[photo.title] = true

				# check that the photo is part of the file we found
				localFile = fsImages.findOne({flickrTitle:photo.title})
				if !localFile
					docpad.log 'warn', 'This image is online but does not match one of your image:' + photo.title + '. You should remove the tag or delete it.'
					return
	
				info = {}
				info.title = photo.title
				info.photoId = photo.id
				tasks.push (complete) ->
					#console.log photo
					FlickPhotoCbk = (err, res) ->
						if err
							console.log err
							info.err = true
						else
							#console.log 'last update: ' + res.photo.dates.lastupdate
							#console.log res.photo.urls.url[0]._content
							info.url = res.photo.urls.url[0]._content
							
							info.mtime = res.photo.dates.lastupdate
						complete()


					client.createRequest('flickr.photos.getInfo',{photo_id:photo.id},true, FlickPhotoCbk).send()

				tasks.push (complete) ->
					#console.log photo
					FlickPhotoCbk = (err, res) ->
						if err
							console.log err
							info.err = true
						else
							for size in res.sizes.size
								# find smarter way...
								if !info.small
									info.small = size.source
								info.big = size.source
								if !info.sDefault && parseInt(size.width) >= config.defaultSize
									#console.log size
									info.sDefault = size.source

						complete()


					client.createRequest('flickr.photos.getSizes',{photo_id:photo.id},true, FlickPhotoCbk).send()
				flickrImages.push info
			

			updateImages = () ->
				
				# verify that each image is on flickr
				# if not: upload it
				# if older: update it
				fsImages.forEach (document)->
					mImage
					flickrTitle = document.get('flickrTitle')

					for image in flickrImages
						if image.title == flickrTitle
							mImage = image
							break
					if mImage
						if mImage.mtime > document.stat.mtime/1000
							#console.log 'image is already up to date on flickr'
						else
							uploadTasks.push (complete) ->
								FlickrUploadCbk = (err,res) ->
									if err
										docpad.log 'warn', 'Replace did not work probably because you need a pro account. You should remove  or untag this image form flickr and re upload it.', err
									else
										# update mtime
										mImage.mtime = document.stat.mtime/1000
									complete()
								# does not work yet: waiting for a pull request.
								client.createRequest('replace',{photo_id:mImage.photoId, photo:fsUtil.createReadStream(document.get('fullPath', {flags: 'r'}))},true, FlickrUploadCbk).send()
					else
						# image needs to be uploaded to flickr and after that, we'll need to get it's characteristics
						# using handleOnePhoto
						#console.log 'image needs to be uploaded'

						uploadTasks.push (complete) ->
							FlickrUploadCbk = (err,res) ->
								if err
									console.log err
								else
									handleOnePhoto {title:flickrTitle,id:res.photoid}, uploadTasks

								complete()

							client.createRequest('upload',{title:flickrTitle, tags:config.flickrTag, photo:fsUtil.createReadStream(document.get('fullPath'), {flags: 'r'})},true, FlickrUploadCbk).send()

				uploadTasks.async()

			updateTasks = new balUtil.Group(updateImages)

			updateTasks.push (complete) ->
				
				FlickrCbk = (err,res) ->
					if err
						console.log err
					else
						# For start, we'll suppose there is only one page of results
						# if there are multiple pages, multiple requests are required
						for photo in res.photos.photo
							do (photo) ->
								handleOnePhoto photo, updateTasks
								
					complete()

				client.createRequest('flickr.photos.search',{tags:config.flickrTag},true, FlickrCbk).send()
			
			collection.forEach (document) ->
				
				if document.get('id').indexOf(flickrImagesPath + '/')>=0
					# warn about possible duplicates (x.png and x.jpg)
					dup = fsImages.findOne({relativeBase:document.get('relativeBase')})
					if dup
						docpad.log('warn', 'Duplicate image was found:' + document.get('id') + ' and ' + dup.get('id') + '. You should clean it or rename it.')
					else
						p = document.get('id').indexOf(flickrImagesPath)>=0
						flickrTitle = document.get('relativeBase').substr(p+flickrImagesPath.length).replace '/',' '
						# set the title as it will be in flickr: docname + file name without extension
						document.set 'flickrTitle', flickrTitle
						fsImages.add document
					#do not write this image to the output folder as it's on flickr :)
					document.set 'write' , false
				
			updateTasks.async()

		docpadReady: (opts,next) ->
			pathUtil = require('path')
			
			{docpad} = opts
			{DocumentModel} = docpad
			
			FlickrImagesPath = @config.flickrImagesPath
			DocumentModel::getFlickrImagesPath = ->
				documentFlickrImagesPath = @get('flickrImagesDirectory') or @get('basename')
				documentFlickrImagesPathNormalized = @getPath(documentFlickrImagesPath, FlickrImagesPath)
				unless documentFlickrImagesPathNormalized.slice(-1) in ['\\','/']
					documentFlickrImagesPathNormalized += pathUtil.sep
				return documentFlickrImagesPathNormalized
			DocumentModel::getFlickrImage = (path) ->
				# Prepare
				document = @
				docpath = document.getFlickrImagesPath()
				#console.log docpath + path
				file = docpad.getFile({relativePath:{$endsWith:docpath + path}})
				if file
					big = file.get('flickrImageBig')
					if !big 
						big = file.get('flickrImage')
				
					return '<a rel=\"'+docpath+'\" class=\"fancybox\" data-fancybox-href=\"' + big + '\" href=\"' + file.get('flickrURL') + '\"><img src=\"' + file.get('flickrImage') + '\"><\/a>'
				else
					return '<i>image not found ' + path + '</i>'
			next()
			