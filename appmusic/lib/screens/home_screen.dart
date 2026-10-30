import 'package:flutter/material.dart';

import '../models/audio_track.dart';
import '../providers/app_controller.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/track_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final recent = controller.tracks.toList()
      ..sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
    final favoriteTracks = controller.favorites.take(8).toList();
    return RefreshIndicator(
      onRefresh: controller.refreshLibrary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const _WelcomeCard(),
          const SizedBox(height: 18),
          _LibrarySummary(controller: controller),
          const SizedBox(height: 28),
          _SectionHeading(
            title: 'Adicionadas recentemente',
            action: TextButton.icon(
              onPressed: controller.refreshLibrary,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Atualizar'),
            ),
          ),
          if (recent.isEmpty)
            const _EmptySection(
              icon: Icons.library_music_outlined,
              message:
                  'Sua biblioteca está vazia. Atualize para procurar músicas.',
            )
          else
            for (final track in recent.take(5))
              TrackTile(
                controller: controller,
                track: track,
                onPlay: () => controller.playTrack(track),
              ),
          const SizedBox(height: 24),
          _SectionHeading(title: 'Seus favoritos'),
          if (favoriteTracks.isEmpty)
            const _EmptySection(
              icon: Icons.favorite_border_rounded,
              message: 'Toque no coração de uma música para salvá-la aqui.',
            )
          else
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: favoriteTracks.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) => _FavoriteCard(
                  track: favoriteTracks[index],
                  onTap: () => controller.playTrack(favoriteTracks[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) => Container(
    height: 194,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF533A91), Color(0xFF2E2450), Color(0xFF201D2D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -24,
          top: -34,
          child: Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .08),
                width: 24,
              ),
            ),
          ),
        ),
        Positioned(
          right: 28,
          bottom: 25,
          child: Icon(
            Icons.graphic_eq_rounded,
            size: 78,
            color: Colors.white.withValues(alpha: .78),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'MÚSICA OFFLINE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Text(
                'Sua trilha.\nSeu ritmo.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                'Sua biblioteca sempre com você.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.white.withValues(alpha: .78)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LibrarySummary extends StatelessWidget {
  const _LibrarySummary({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.headphones_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${controller.tracks.length} músicas',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  '${controller.catalog.playlists.length} playlists · '
                  '${controller.catalog.favorites.length} favoritos',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.track, required this.onTap});

  final AudioTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 128,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArtworkTile(track: track, size: 128),
          const SizedBox(height: 9),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(child: Text(message)),
      ],
    ),
  );
}
