import 'dart:math';

/// A short cryptographically-random token to append to private-bucket
/// object paths (booking-images, insurance-documents). Those buckets grant
/// blanket bucket-wide read to the `anon` role because the garage/fleet
/// admin panels authenticate against their own bcrypt tables via an edge
/// function rather than Supabase Auth, so there's no auth.uid() to scope a
/// row-level policy against — the only thing standing between a private
/// document/photo and anyone with the (public) anon key is whether its
/// storage path can be guessed. A bare millisecond timestamp is guessable
/// within a short brute-force window; mixing in this token isn't.
String secureStorageToken([int length = 20]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random.secure();
  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}
