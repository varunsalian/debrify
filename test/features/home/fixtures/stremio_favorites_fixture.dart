import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';

StremioTvChannel channel(String id, {String type = 'movie'}) =>
    StremioTvChannel(
      id: id,
      displayName: 'One',
      addon: StremioAddon(
        id: 'addon',
        name: 'Addon',
        manifestUrl: '',
        baseUrl: '',
      ),
      catalog: StremioAddonCatalog(id: 'catalog', name: 'Catalog', type: type),
      channelNumber: 1,
      items: [StremioMeta(id: 'item:$id', name: 'Item', type: type)],
    );
