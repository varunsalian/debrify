class StreamProviders {
  static final Map<String, dynamic> providers = {
    'service111477': {
      'name': '111477.xyz',
      'movie': null,
      'tv': null,
    },
    'webstreamr': {
      'name': 'WebStreamr',
      'movie': null,
      'tv': null,
    },
    'vidlink': {
      'name': 'VidLink',
      'movie': (id) => 'https://vidlink.pro/movie/$id',
      'tv': (id, s, e) => 'https://vidlink.pro/tv/$id/$s/$e',
    },
    'vixsrc': {
      'name': 'VixSrc',
      'movie': (id) => 'https://vixsrc.to/movie/$id/',
      'tv': (id, s, e) => 'https://vixsrc.to/tv/$id/$s/$e/',
    },
    'vidnest': {
      'name': 'VidNest',
      'movie': (id) => 'https://vidnest.fun/movie/$id',
      'tv': (id, s, e) => 'https://vidnest.fun/tv/$id/$s/$e',
    },
    'videasy': {
      'name': 'Videasy',
      'movie': null,
      'tv': null,
    },
    'vidsrc': {
      'name': 'Vidsrc',
      'movie': null,
      'tv': null,
    },
  };
}
