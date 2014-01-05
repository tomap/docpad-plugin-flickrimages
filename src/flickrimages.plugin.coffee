# Export Plugin
module.exports = (BasePlugin) ->
	
	# Define Flickr Image Plugin
	class FlickrImagesPlugin extends BasePlugin
		# Plugin name
		name: 'flickrimages'

		# Plugin config
		config:
			# image in this path will be uploaded to flickr
			flickrImagesPath: 'flickr-images'
			# when images are uploaded to flickr, this tag will be added
			flickrTag: 'docpad'
			# images will be displayed with this size if available
			defaultSize: 500
		

		renderBefore: (opts,next) ->
		
			# Prepare
			docpad = @docpad

			docpad.log 'debug', 'Start preparing flickr image links'

			config = @config
			pathUtil = require('path')
			fsUtil = require('fs')
			flickr = require('flickr-with-uploads')
			TaskGroup = require('taskgroup').TaskGroup
			
			env = process.env
			
			api = flickr(env.flickrKey, env.flickrSecret, env.flickrOAToken, env.flickrOASecret)
			
			flickrImages = []
			{collection,templateData} = opts

			# Fetch our configuration
			flickrImagesPath = config.flickrImagesPath
			
			# create an empty files collection that we'll fill with 'valid' images
			fsImages = new docpad.FilesCollection()
			
			uniqueFlickrTitle = {}	

			endTask = () ->
				docpad.log 'debug', 'finish preparing flickr image links'
			 
				fsImages.forEach (document)->
					try
						mImage
						flickrTitle = document.get('flickrTitle')

						for image in flickrImages
							if image.title == flickrTitle
								mImage = image
								break
						if mImage
							if mImage.mtime > document.stat.mtime/1000
								docpad.log 'debug', 'Image is already up to date on flickr', flickrTitle
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
					catch e
						console.log e
				docpad.log 'debug', 'finished managing flickr images'
				
				next()


			uploadTasks = new TaskGroup()
			uploadTasks.once 'complete', endTask
			
			handleOnePhoto = (photo, tasks) ->
				docpad.log 'debug', 'handle image', photo.title
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
				tasks.addTask (complete) ->
					docpad.log 'debug', 'Calling flickr.photos.getInfo about' , photo.title
					
					FlickPhotoCbk = (err, res) ->
						if err
							docpad.log 'error', 'Error in flickr.photos.getInfo', err
							info.err = true
						else
							
							info.url = res.photo.urls.url[0]._content
							info.mtime = res.photo.dates.lastupdate
							docpad.log 'debug', 'flickr.photos.getInfo returned info about', photo.title
							docpad.log 'debug', 'last update' , info.mtime
							docpad.log 'debug', 'url' , info.url
							
						complete()


					api({method:'flickr.photos.getInfo',photo_id:photo.id},FlickPhotoCbk)

				tasks.addTask (complete) ->
					#console.log photo
					FlickPhotoCbk = (err, res) ->
						if err
							docpad.log 'error', 'Error in flickr.photos.getSizes', err
							info.err = true
						else
							for size in res.sizes.size
								# find smarter way...
								if !info.small
									info.small = size.source
								info.big = size.source
								if !info.sDefault && parseInt(size.width) >= config.defaultSize
									info.sDefault = size.source
							docpad.log 'debug' , 'flickr.photos.getSizes returned sizes'
						complete()


					api({method:'flickr.photos.getSizes',photo_id:photo.id}, FlickPhotoCbk)
				flickrImages.push info
			

			updateImages = () ->
				docpad.log 'debug', 'update images'
				# verify that each image is on flickr
				# if not: upload it
				# if older: update it

				docpad.log 'debug', 'loop in valid images' 
				
				fsImages.forEach (document)->
					mImage
					
					flickrTitle = document.get('flickrTitle')

					docpad.log 'debug', 'update image', flickrTitle 
				
					for image in flickrImages
						if image.title == flickrTitle
							mImage = image
							break
					
					if mImage
						if mImage.mtime > document.stat.mtime/1000
							docpad.log 'debug', 'image is already up to date on flickr', flickrTitle
						else
							docpad.log 'info', 'image needs to be updated on flickr', flickrTitle
							uploadTasks.addTask (complete) ->
								FlickrUploadCbk = (err,res) ->
									if err
										docpad.log 'warn', 'Replace did not work probably because you need a pro account. You should remove or untag this image form flickr and re upload it.', err
									else
										# update mtime
										mImage.mtime = document.stat.mtime/1000
									complete()
								# does not work yet: waiting for a pull request.
								api({method:'replace',photo_id:mImage.photoId, photo:fsUtil.createReadStream(document.get('fullPath', {flags: 'r'}))}, FlickrUploadCbk)
					else
						# image needs to be uploaded to flickr and after that, we'll need to get it's characteristics
						# using handleOnePhoto
						docpad.log 'info', 'Image needs to be uploaded on flickr', flickrTitle

						uploadTasks.addTask (complete) ->
							
							FlickrUploadCbk = (err,res) ->
								smallTaskGroup = new TaskGroup()

								smallTaskGroup.once 'complete' , complete

								if err
									docpad.log 'error', 'Error while uploading new image', err
								else
									docpad.log 'debug', 'image has been uploaded on flickr', flickrTitle
							
									handleOnePhoto {title:flickrTitle,id:res.photoid}, smallTaskGroup

								smallTaskGroup.run()

							api({method:'upload',title:flickrTitle, tags:config.flickrTag, photo:fsUtil.createReadStream(document.get('fullPath'), {flags: 'r'})}, FlickrUploadCbk)
				
				uploadTasks.run()

			updateTasks = new TaskGroup()

			updateTasks.once 'complete', updateImages

			updateTasks.addTask (complete) ->
							
				FlickrCbk = (err,res) ->
					
					docpad.log 'debug', 'flickr.photos.search callback'
					localTasks = new TaskGroup()
					localTasks.once 'complete', complete
					if err
						docpad.log 'error' , err
					else
						# For start, we'll suppose there is only one page of results
						# if there are multiple pages, multiple requests are required
						for photo in res.photos.photo
							do (photo) ->
								docpad.log 'debug', 'found one photo online: ' + photo.title
								handleOnePhoto photo, localTasks

					localTasks.run()
					

				api({method:'flickr.photos.search',tags:config.flickrTag},FlickrCbk)
			
			collection.forEach (document) ->
				
				if document.get('relativePath').indexOf(flickrImagesPath + '/')>=0
					# warn about possible duplicates (x.png and x.jpg)
					# all this code is crap
					dup = fsImages.findOne({relativeBase:document.get('relativeBase')})
					if dup && dup.get('id') != document.get('id')
						docpad.log 'warn', 'Duplicate image was found:' + document.get('relativePath') + ' and ' + dup.get('relativePath') + '. You should clean it or rename it.'
					else
						p = document.get('relativePath').indexOf(flickrImagesPath)
						flickrTitle = document.get('relativeBase').substr(p+flickrImagesPath.length).replace(/\//g,' ').trim()
						# set the title as it will be in flickr: docname + file name without extension
						docpad.log 'debug' , 'Found one valid image: ' , flickrTitle

						document.set 'flickrTitle', flickrTitle
						fsImages.add document
					#do not write this image to the output folder as it's on flickr :)
					document.set 'write' , false
			docpad.log 'debug', 'end of search valid images'
			
			updateTasks.run()
			
		docpadReady: (opts,next) ->

			pathUtil = require('path')
			
			{docpad} = opts
			{DocumentModel} = docpad
			FlickrImagesPath = @config.flickrImagesPath

			getFlickrImagesPath = (docModel) ->
				try 
					documentFlickrImagesPath = docModel.get('flickrImagesDirectory') or docModel.get('basename')
					documentFlickrImagesPathNormalized = docModel.getPath(documentFlickrImagesPath, FlickrImagesPath)
					unless documentFlickrImagesPathNormalized.slice(-1) in ['\\','/']
						documentFlickrImagesPathNormalized += pathUtil.sep
				catch e
					console.log e
				return documentFlickrImagesPathNormalized

			DocumentModel::getFlickrImage = (path) ->
				# Prepare
				document = @
				docpath = getFlickrImagesPath(document)
				console.log docpath + path
				file = docpad.getFile({relativePath:{$endsWith:docpath + path}})
				if file
					big = file.get('flickrImageBig')
					if !big 
						big = file.get('flickrImage')
				
					return '<a rel=\"'+docpath+'\" class=\"fancybox\" data-fancybox-href=\"' + big + '\" href=\"' + file.get('flickrURL') + '\"><img src=\"' + file.get('flickrImage') + '\"><\/a>'
				else
					return '<i>image not found ' + path + '</i>'
			
			next()
