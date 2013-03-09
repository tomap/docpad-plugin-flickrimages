# Export Plugin
module.exports = (BasePlugin) ->
	# Define Associated Files Plugin
	class FlickrImagePlugin extends BasePlugin
		# Plugin name
		name: 'flickrimages'

		# Plugin config
		config:
			flickrImagesPath: 'flickr-images'
			flickrTag: 'docpad'

		# DocPad is ready now
		# Lets use this time to extend our file model
		renderBefore: (opts,next) ->
			# Prepare
			docpad = @docpad
			config = @config
			pathUtil = require('path')
			fsUtil = require('fs')
			flickr = require('flickr-with-uploads').Flickr
			balUtil = require('bal-util');
			
			env = process.env
			
			client = new flickr(env.flickrKey, env.flickrSecret,env.flickrOAToken,env.flickrOASecret)
			fsImages = []
			flickrImages = []
			{collection,templateData} = opts
			fsImages = new docpad.FilesCollection()
			
			# Fetch our configuration
			associatedFilesPath = config.flickrImagesPath
			createAssociatedFilesPath = config.createAssociatedFilesPath

			updateImages = () ->
				
				# verify that each image is on flickr
				# if not: upload it
				# if older: update it
				FlickrUploadCbk = (err,res) ->
					console.log err
					console.log res


				fsImages.forEach (document)->
					mImage
					p = document.get('id').indexOf(associatedFilesPath)>=0
					epath = document.get('relativeBase').substr(p+associatedFilesPath.length).replace '/',' '
					#console.log epath
					for image in flickrImages
						if image.title == epath
							mImage = image
							break
					if mImage
						if mImage.mtime > document.stat.mtime/1000
							#console.log 'image is already up to date on flickr'
							document.set 'flickrURL' , mImage.url
							if(mImage.s500)
								document.set 'flickrImage',mImage.s500
								document.set 'flickrImageBig',mImage.big
							else
								document.set 'flickrImage',mImage.big
						else
							console.log 'image on flickr is out of date'
							# TODO
					else
						# image needs to be uploaded to flickr and after that, we'll need to get it's characteristics
						client.createRequest('upload',{title:epath, tags:config.flickrTag, photo:fsUtil.createReadStream(document.get('fullPath'), {flags: 'r'})},true, FlickrUploadCbk).send()

				return next()

			tasks = new balUtil.Group(updateImages)

			tasks.push (complete) ->
				
				FlickrCbk = (err,res) ->
					if err
						console.log err
					else
						# For start, we'll suppose there is only one page of results
						# if there are multiple pages, multiple requests are required
						for photo in res.photos.photo
							do (photo) ->
								console.log photo.title
								info = {}
								info.title = photo.title
								tasks.push (complete) ->
									#console.log photo
									FlickPhotoCbk = (err, res) ->
										if(err)
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
										if(err)
											console.log err
											info.err = true
										else
											for size in res.sizes.size
												# find smarter way...
												if(!info.small)
													info.small = size.source
												info.big = size.source
												if(!info.s500 && parseInt(size.width) >= 500)
													#console.log size
													info.s500 = size.source

										complete()


									client.createRequest('flickr.photos.getSizes',{photo_id:photo.id},true, FlickPhotoCbk).send()
								flickrImages.push info
					complete()

				client.createRequest('flickr.photos.search',{tags:config.flickrTag},true, FlickrCbk).send()
			
		
			collection.forEach (document) ->
				
				if(document.get('id').indexOf(associatedFilesPath)>=0)
					fsImages.add document
					#do not write this image as it's on flickr :)
					document.set 'write' , false
				
			tasks.async()

		docpadReady: (opts,next) ->
			pathUtil = require('path')
			
			{docpad} = opts
			{DocumentModel} = docpad
			
			associatedFilesPath = @config.flickrImagesPath
			DocumentModel::getAssociatedFilesPath = ->
				documentAssociatedFilesPath = @get('flickrImagesDirectory') or @get('basename')
				documentAssociatedFilesPathNormalized = @getPath(documentAssociatedFilesPath, associatedFilesPath)
				unless documentAssociatedFilesPathNormalized.slice(-1) in ['\\','/']
					documentAssociatedFilesPathNormalized += pathUtil.sep
				return documentAssociatedFilesPathNormalized
			DocumentModel::getFlickrImage = (path) ->
				# Prepare
				document = @
				docpath = document.getAssociatedFilesPath()
				#console.log docpath + path
				file = docpad.getFile({relativePath:{$endsWith:docpath + path}})
				if(file)
					big = file.get('flickrImageBig')
					if(!big) 
						big = file.get('flickrImage')
				
					return '<a rel=\"'+docpath+'\" class=\"fancybox\" data-fancybox-href=\"' + big + '\" href=\"' + file.get('flickrURL') + '\"><img src=\"' + file.get('flickrImage') + '\"><\/a>'
				else
					return '<i>image not found ' + path + '</i>'
			next()
			