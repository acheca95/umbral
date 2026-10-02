import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbral_rpg/cloud.dart';
import 'package:umbral_rpg/game.dart';
import 'package:umbral_rpg/world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CloudService cloud;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = CloudService(await SharedPreferences.getInstance())
      ..uid = 'player'
      ..database = FakeFirebaseFirestore()
      ..available = true;
  });
  tearDown(() => cloud.dispose());
  test('Cloud upload is opt-in and updates revision atomically', () async {
    final game = Game(HeroClass.ranger);
    expect(await cloud.upload(game), isFalse);
    expect(await cloud.upload(game, replace: true), isTrue);
    expect(cloud.autoSync, isTrue);
    expect(cloud.revision, 1);
    game.gold = 70;
    expect(await cloud.upload(game), isTrue);
    expect(cloud.revision, 2);
    final saved = await cloud.download();
    expect(saved!.gold, 70);
    expect(saved.heroClass, HeroClass.ranger);
  });
  test('Newer remote revision never gets silently overwritten', () async {
    final game = Game(HeroClass.guardian);
    await cloud.upload(game, replace: true);
    await cloud.saveRef.update({'revision': 2, 'level': 4});
    await cloud.refresh();
    expect(cloud.revision, 1);
    expect(await cloud.upload(game), isFalse);
    expect(cloud.error, contains('otro dispositivo'));
    expect((await cloud.saveRef.get()).data()!['level'], 4);
    expect(await cloud.upload(game, replace: true), isTrue);
    expect(cloud.revision, 3);
  });
  test('Changing account does not bind an unrelated local save', () async {
    await cloud.upload(Game(HeroClass.guardian), replace: true);
    cloud.uid = 'another';
    expect(cloud.autoSync, isFalse);
    expect(await cloud.upload(Game(HeroClass.ranger)), isFalse);
    expect((await cloud.saveRef.get()).exists, isFalse);
  });
  test(
    'Invalid remote save fails explicitly without replacing a local game',
    () async {
      await cloud.saveRef.set({
        'revision': 1,
        'payload': '{"version":999}',
        'level': 1,
        'heroClass': 0,
      });
      expect(await cloud.download(), isNull);
      expect(cloud.error, isNotNull);
      expect(cloud.autoSync, isFalse);
    },
  );
}
