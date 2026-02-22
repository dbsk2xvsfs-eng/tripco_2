enum UserProfile { solo, couple, family, kids }

extension UserProfileUi on UserProfile {
  String get label {
    switch (this) {
      case UserProfile.solo:
        return "Solo";
      case UserProfile.couple:
        return "Couple";
      case UserProfile.family:
        return "Family";
      case UserProfile.kids:
        return "Family with kids";
    }
  }

  String get emoji {
    switch (this) {
      case UserProfile.solo:
        return "🧍";
      case UserProfile.couple:
        return "🧑‍🤝‍🧑";
      case UserProfile.family:
        return "👨‍👩‍👧";
      case UserProfile.kids:
        return "👨‍👩‍👧‍👦";
    }
  }
}
