import 'package:flutter/material.dart';
import 'package:indriver_clone/models/address.dart';
import 'package:indriver_clone/models/place_predications.dart';
import 'package:indriver_clone/providers/handle.dart';
import 'package:indriver_clone/util/config.dart';
import 'package:indriver_clone/util/request_assist.dart';
import 'package:provider/provider.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key, required this.pickup}) : super(key: key);
  final bool pickup;

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final location = Provider.of<AppHandler>(context, listen: false);
      _searchController.text = widget.pickup
          ? (location.pickupLocation?.placeName ?? '')
          : (location.destinationLocation?.placeName ?? '');
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: SafeArea(
          child: Consumer<AppHandler>(
            builder: (_, location, __) => Column(
              children: [
                Column(
                  children: [
                    ListTile(
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          location.clearPredictions();
                          Navigator.pop(context);
                        },
                      ),
                      title: Text(
                        widget.pickup
                            ? 'Search start point'
                            : 'Search end point',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.search),
                      title: TextFormField(
                        controller: _searchController,
                        autofocus: true,
                        onChanged: (val) => location.findPlace(val),
                        decoration: InputDecoration(
                          hintText:
                              widget.pickup ? 'Pickup location' : 'Destination',
                        ),
                      ),
                    ),
                  ],
                ),
                location.predictionList.isEmpty
                    ? Container()
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: ListView.separated(
                          itemBuilder: (context, index) => PredictionTile(
                            destination: !widget.pickup,
                            prediction: location.predictionList[index],
                          ),
                          separatorBuilder: (context, index) =>
                              const Divider(thickness: 2),
                          itemCount: location.predictionList.length,
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PredictionTile extends StatelessWidget {
  const PredictionTile({
    Key? key,
    required this.prediction,
    required this.destination,
  }) : super(key: key);

  final Prediction prediction;
  final bool destination;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => getPlaceAddress(prediction.id!, context),
      child: Column(
        children: [
          const SizedBox(width: 14.0),
          Row(
            children: [
              const Icon(Icons.add_location),
              const SizedBox(width: 14.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prediction.mainText!,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3.0),
                    Text(
                      prediction.subtitle!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 14.0),
        ],
      ),
    );
  }

  void getPlaceAddress(String placeId, BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final String placeDetails =
        "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=${Config.api_key}";

    var response = await RequestAssistant.getRequest(placeDetails);

    Navigator.pop(context);

    if (response == 'failed') return;

    if (response['status'] == 'OK') {
      Address address = Address(
        placeId: placeId,
        placeName: response["result"]['name'],
        latitude: response['result']['geometry']['location']['lat'],
        longitude: response['result']['geometry']['location']['lng'],
      );

      if (destination) {
        Provider.of<AppHandler>(context, listen: false)
            .updateDestinationLocationAdress(address);
        Provider.of<AppHandler>(context, listen: false).clearPredictions();
        await Provider.of<AppHandler>(context, listen: false)
            .getDirection(context);
        Navigator.pop(context, 'direction');
      } else {
        Provider.of<AppHandler>(context, listen: false)
            .updatePickupLocationAdress(address);
        Provider.of<AppHandler>(context, listen: false).clearPredictions();
        Navigator.pop(context);
      }
    } else {
      Provider.of<AppHandler>(context, listen: false).clearPredictions();
    }
  }
}