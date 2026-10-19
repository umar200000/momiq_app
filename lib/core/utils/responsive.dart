/// CSS `clamp(min, preferred, max)` ning Dart ekvivalenti.
double cssClamp(double min, double preferred, double max) {
  if (preferred < min) return min;
  if (preferred > max) return max;
  return preferred;
}
