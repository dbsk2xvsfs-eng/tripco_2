import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../models/user_profile.dart';

class ProfileSheet extends StatelessWidget {
  final UserProfile current;
  final ValueChanged<UserProfile> onSelected;

  const ProfileSheet({
    super.key,
    required this.current,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.travelWith,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...UserProfile.values.map((p) {
              final selected = p == current;
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
                  title: Text(p.label),
                  trailing: selected ? const Icon(Icons.check_circle) : null,
                  onTap: () {
                    onSelected(p);
                    Navigator.of(context).pop();
                  },
                ),
              );
            }),
            const SizedBox(height: 6),
            Text(
              s.tailor,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
