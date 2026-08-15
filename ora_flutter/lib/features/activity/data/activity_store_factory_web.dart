import 'activity_store.dart';
import 'web_activity_store.dart';

ActivityStore createActivityStoreForPlatform() => WebActivityStore();
