# Flickr Images Plugin for DocPad
This plugin will handle uploading images to flickr and linking them to your site in [DocPad](https://docpad.org)

## Work in progress

Lots of thing to do:

Currently the output has been made to work with fancybox, which is fine for me, but not for everyone.

---


## Install

```
npm install --save docpad-plugin-flickrimages
```



## Usage

The way it works is by looking into `src/files/flickr-images/#{document.flickrImagesDirectory or document.basename}` for files. Where `flickrImagesDirectory` is set in your document's meta data, and if it doesn't exist it will use the document's basename (e.g. the basename of `my-holiday-2012.html.eco` is `my-holiday-2012`). Any files inside that path will be associated to your document, and retrievable by `@getDocument().getAssociatedFiles()`

Lets see how this works, we have the document `src/documents/my-holiday-2012.html.eco`:

``` html
---
title: My Holiday in 2012
---

<h2>Here are some great photos from our trip</h2>

<%- @getDocument().getFlickrImage('The Eiffel Tour.jpg') %>
```

Then we will stick The Eiffel Tour.jpg in this folder: `src/files/flickr-images/my-holiday-2012`. And we'll end up with the rendered result:

``` html
<h2>Here are some great photos from our trip</h2>

<a rel="flickr-images/my-holiday-2012/" class="fancybox" data-fancybox-href="http://farm9.staticflickr.com/8528/8521291746_fc4e33b592_b.jpg" href="http://www.flickr.com/photos/92861950@N07/8521291746/"><img src="http://farm9.staticflickr.com/8528/8521291746_fc4e33b592.jpg"></a>

```

Ins't that cool?


## History
You can discover the history inside the `History.md` file


## License
Licensed under the incredibly [permissive](http://en.wikipedia.org/wiki/Permissive_free_software_licence) [MIT License](http://creativecommons.org/licenses/MIT/)
<br/>Copyright &copy; 2013+ [Thomas Piart](http://tpî.eu)
