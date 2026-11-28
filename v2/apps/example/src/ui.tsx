// The few building blocks every screen shares. Plain React Native
// components; nothing here is needed to use TurboImage.
import type { ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MONOSPACE, SPACING, useTheme } from './theme';

// A titled screen. `onBack` adds the back button (Android's hardware back
// is handled once, in App.tsx). `scroll={false}` for screens that bring
// their own list, which must not sit inside a ScrollView.
export function Screen({
  title,
  onBack,
  scroll = true,
  children,
}: {
  title: string;
  onBack?: () => void;
  scroll?: boolean;
  children: ReactNode;
}) {
  const theme = useTheme();
  return (
    <SafeAreaView
      edges={['top', 'left', 'right']}
      style={[styles.screen, { backgroundColor: theme.background }]}
    >
      <View style={[styles.header, { borderBottomColor: theme.separator }]}>
        {onBack && (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Back"
            hitSlop={12}
            onPress={onBack}
            style={styles.back}
          >
            <Text style={[styles.backText, { color: theme.accent }]}>‹ Back</Text>
          </Pressable>
        )}
        <Text style={[styles.headerTitle, { color: theme.text }]} numberOfLines={1}>
          {title}
        </Text>
      </View>
      {scroll ? (
        <ScrollView contentContainerStyle={styles.content}>{children}</ScrollView>
      ) : (
        <View style={styles.fill}>{children}</View>
      )}
    </SafeAreaView>
  );
}

// A group of related demos, on a card.
export function Section({
  title,
  caption,
  children,
}: {
  title: string;
  caption?: string;
  children: ReactNode;
}) {
  const theme = useTheme();
  return (
    <View style={styles.section}>
      <Text style={[styles.sectionTitle, { color: theme.secondaryText }]}>
        {title.toUpperCase()}
      </Text>
      <View style={[styles.card, { backgroundColor: theme.card }]}>
        {caption && <Caption>{caption}</Caption>}
        {children}
      </View>
    </View>
  );
}

export function Caption({ children }: { children: ReactNode }) {
  const theme = useTheme();
  return <Text style={[styles.caption, { color: theme.secondaryText }]}>{children}</Text>;
}

export function Code({ children }: { children: ReactNode }) {
  const theme = useTheme();
  return (
    <Text selectable style={[styles.code, { color: theme.text }]}>
      {children}
    </Text>
  );
}

// One-of-many, as wrapping chips. Options are strings, or `[value, label]`.
export function Choice<T extends string | number>({
  label,
  options,
  value,
  onChange,
}: {
  label?: string;
  options: readonly (T | readonly [T, string])[];
  value: T;
  onChange: (value: T) => void;
}) {
  const theme = useTheme();
  return (
    <View style={styles.choice}>
      {label && <Text style={[styles.choiceLabel, { color: theme.text }]}>{label}</Text>}
      <View style={styles.chips}>
        {options.map((option) => {
          const [optionValue, optionLabel] = Array.isArray(option)
            ? (option as readonly [T, string])
            : [option as T, String(option)];
          const selected = optionValue === value;
          return (
            <Pressable
              key={String(optionValue)}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              onPress={() => onChange(optionValue)}
              style={[
                styles.chip,
                selected
                  ? { backgroundColor: theme.accent, borderColor: theme.accent }
                  : { borderColor: theme.separator },
              ]}
            >
              <Text style={[styles.chipText, { color: selected ? '#ffffff' : theme.text }]}>
                {optionLabel}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

export function Toggle({
  label,
  value,
  onChange,
  note,
}: {
  label: string;
  value: boolean;
  onChange: (value: boolean) => void;
  note?: string;
}) {
  const theme = useTheme();
  return (
    <View style={styles.toggle}>
      <View style={styles.fill}>
        <Text style={[styles.choiceLabel, { color: theme.text }]}>{label}</Text>
        {note && <Caption>{note}</Caption>}
      </View>
      <Switch value={value} onValueChange={onChange} />
    </View>
  );
}

export function Button({
  title,
  onPress,
  disabled,
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
}) {
  const theme = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        { borderColor: theme.accent, opacity: disabled ? 0.4 : pressed ? 0.6 : 1 },
      ]}
    >
      <Text style={[styles.buttonText, { color: theme.accent }]}>{title}</Text>
    </Pressable>
  );
}

export function ButtonRow({ children }: { children: ReactNode }) {
  return <View style={styles.chips}>{children}</View>;
}

// A tappable row that leads to another screen.
export function NavRow({
  title,
  subtitle,
  onPress,
}: {
  title: string;
  subtitle: string;
  onPress: () => void;
}) {
  const theme = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [styles.navRow, { opacity: pressed ? 0.6 : 1 }]}
    >
      <View style={styles.fill}>
        <Text style={[styles.navTitle, { color: theme.text }]}>{title}</Text>
        <Caption>{subtitle}</Caption>
      </View>
      <Text style={[styles.chevron, { color: theme.secondaryText }]}>›</Text>
    </Pressable>
  );
}

// A label and a value. `kind` says where the number comes from, so measured
// values are never confused with unavailable ones.
export function Stat({
  label,
  value,
  kind = 'measured',
}: {
  label: string;
  value: ReactNode;
  kind?: 'measured' | 'unavailable';
}) {
  const theme = useTheme();
  return (
    <View style={styles.stat}>
      <Text style={[styles.statLabel, { color: theme.text }]}>{label}</Text>
      <Text
        style={[
          styles.statValue,
          { color: kind === 'unavailable' ? theme.secondaryText : theme.text },
        ]}
      >
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  fill: { flex: 1 },
  header: {
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 72,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerTitle: { fontSize: 17, fontWeight: '600' },
  back: { position: 'absolute', left: SPACING, top: 0, bottom: 0, justifyContent: 'center' },
  backText: { fontSize: 17 },
  content: { padding: SPACING, gap: 24, paddingBottom: 48 },
  section: { gap: 6 },
  sectionTitle: { fontSize: 13, marginLeft: SPACING },
  card: { borderRadius: 12, padding: SPACING, gap: 12 },
  caption: { fontSize: 13, lineHeight: 18 },
  code: { fontFamily: MONOSPACE, fontSize: 12, lineHeight: 17 },
  choice: { gap: 6 },
  choiceLabel: { fontSize: 15, fontWeight: '500' },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 14,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  chipText: { fontSize: 13 },
  toggle: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  button: { borderWidth: 1, borderRadius: 8, paddingHorizontal: 12, paddingVertical: 7 },
  buttonText: { fontSize: 14, fontWeight: '500' },
  navRow: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 4 },
  navTitle: { fontSize: 17 },
  chevron: { fontSize: 22 },
  stat: { flexDirection: 'row', justifyContent: 'space-between', gap: 12 },
  statLabel: { fontSize: 14, flexShrink: 1 },
  statValue: { fontSize: 14, fontFamily: MONOSPACE, textAlign: 'right', flexShrink: 1 },
});
