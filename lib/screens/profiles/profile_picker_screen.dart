import 'package:flutter/material.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';

class ProfilePickerScreen extends StatelessWidget {
  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onSelected;
  final VoidCallback? onManage;

  const ProfilePickerScreen({
    super.key,
    required this.profiles,
    required this.onSelected,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Who’s watching?',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 760
                            ? 4
                            : constraints.maxWidth >= 480
                            ? 3
                            : 2;
                        return GridView.builder(
                          shrinkWrap: true,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 20,
                                crossAxisSpacing: 20,
                                childAspectRatio: .82,
                              ),
                          itemCount: profiles.length,
                          itemBuilder: (context, index) => _ProfileCard(
                            profile: profiles[index],
                            autofocus: index == 0,
                            onTap: () => onSelected(profiles[index]),
                          ),
                        );
                      },
                    ),
                  ),
                  if (onManage != null) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: onManage,
                      icon: const Icon(Icons.manage_accounts_rounded),
                      label: const Text('Manage profiles'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final UserProfile profile;
  final bool autofocus;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.profile,
    required this.autofocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: autofocus,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: <Color>[colors.primary, colors.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      _avatarIcon(profile.avatarKey, profile.role),
                      size: 64,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (profile.hasPin)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.lock_rounded, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _avatarIcon(String? key, UserProfileRole role) =>
      switch (key) {
        'child' => Icons.child_care_rounded,
        'movie' => Icons.movie_filter_rounded,
        'rocket' => Icons.rocket_launch_rounded,
        'sports' => Icons.sports_esports_rounded,
        'music' => Icons.headphones_rounded,
        _ =>
          role == UserProfileRole.child
              ? Icons.child_care_rounded
              : Icons.person_rounded,
      };
}
