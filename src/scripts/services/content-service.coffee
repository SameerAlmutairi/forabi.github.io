_ = require 'lodash'
module.exports = [
    '$http', '$rootScope', 'CacheService', '$q', '$log',
    ($http, $rootScope, CacheService, $q, $log) ->
        $log.debug 'Content Service ready'
        getBlog: ->
            fn = =>
                $http.get 'config.json', cache: yes
                .then (res) -> $rootScope.blog = res.data
            CacheService.get 'blog', 'blog', fn
        getPage: (page = 1) ->
            fn = =>
                @getBlog()
                .then ->
                    $http.get "content/posts.#{page}.json", cache: yes
                    .then (res) ->
                        _.map res.data, (post, i, collection) ->
                            _.extend post,
                                url: "posts/#{post.id}"
                                page: page
                                next: try collection[i + 1].id
                                prev: try collection[i - 1].id
            CacheService.get 'pages', page, fn
        getPost: (id, page = 1) ->
            fn = =>
                @getPage(page).then (posts) ->
                    $q.all [
                        post = _.findWhere posts, id: id
                        $http.get "content/#{post.filename}", cache: yes
                    ]
                .then (all) ->
                    _.extend all[0], text: all[1].data
            CacheService.get 'posts', id, fn
]