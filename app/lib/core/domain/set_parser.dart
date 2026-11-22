/// 训练组解析与动作中文别名：与 fitfuel.strength 对齐。
library;

class ParsedSet {
  final String name;
  final double weightKg;
  final int reps;
  final double? rpe;
  const ParsedSet(this.name, this.weightKg, this.reps, this.rpe);
}

/// 解析 "卧推 80 5 @8" / "Barbell Squat 100kg x 3" / "引体向上 0 10"。
ParsedSet? parseSetSpec(String spec) {
  final s = spec.trim();
  final re = RegExp(
    r'^(.+?)\s+(\d+(?:\.\d+)?)\s*(?:kg|公斤|千克)?\s*(?:[x×*]\s*)?(\d+)\s*(?:@\s*(\d+(?:\.\d+)?))?$',
    caseSensitive: false,
  );
  final m = re.firstMatch(s);
  if (m == null) return null;
  return ParsedSet(
    m.group(1)!.trim(),
    double.parse(m.group(2)!),
    int.parse(m.group(3)!),
    m.group(4) == null ? null : double.parse(m.group(4)!),
  );
}

/// 中文别名 → 英文搜索关键词（按顺序尝试）。与 fitfuel.exercises.ZH_ALIASES 对齐。
const zhAliases = <String, List<String>>{
  '卧推': ['barbell bench press', 'bench press'],
  '平板卧推': ['barbell bench press'],
  '杠铃卧推': ['barbell bench press'],
  '上斜卧推': ['barbell incline bench press', 'incline bench press'],
  '哑铃卧推': ['dumbbell bench press'],
  '哑铃上斜卧推': ['dumbbell incline bench press'],
  '深蹲': ['barbell squat', 'squat'],
  '杠铃深蹲': ['barbell squat'],
  '颈前蹲': ['goblet squat'],
  '硬拉': ['barbell deadlift', 'deadlift'],
  '杠铃硬拉': ['barbell deadlift'],
  '罗马尼亚硬拉': ['barbell romanian deadlift', 'romanian deadlift'],
  '直腿硬拉': ['stiff leg deadlift'],
  '肩推': ['barbell shoulder press', 'shoulder press'],
  '推举': ['barbell shoulder press', 'shoulder press'],
  '站姿推举': ['barbell shoulder press', 'standing barbell press'],
  '坐姿肩推': ['seated shoulder press'],
  '哑铃肩推': ['dumbbell shoulder press'],
  '引体向上': ['pull up'],
  '反手引体': ['chin up'],
  '高位下拉': ['lat pulldown'],
  '坐姿划船': ['seated row'],
  '划船': ['barbell row', 'row'],
  '杠铃划船': ['barbell row'],
  '哑铃划船': ['dumbbell row'],
  '弯举': ['biceps curl'],
  '二头弯举': ['biceps curl'],
  '杠铃弯举': ['barbell biceps curl'],
  '锤式弯举': ['hammer curl'],
  '三头下压': ['triceps pushdown'],
  '绳索下压': ['rope triceps pushdown'],
  '臂屈伸': ['dip'],
  '双杠臂屈伸': ['dip'],
  '腿举': ['leg press'],
  '腿弯举': ['leg curl'],
  '腿屈伸': ['leg extension'],
  '侧平举': ['lateral raise'],
  '哑铃侧平举': ['dumbbell lateral raise'],
  '面拉': ['face pull'],
  '臀推': ['hip thrust'],
  '臀桥': ['glute bridge'],
  '保加利亚分腿蹲': ['split squat'],
  '分腿蹲': ['split squat'],
  '箭步蹲': ['lunge'],
  '俯卧撑': ['push up'],
  '卷腹': ['crunch'],
  '平板支撑': ['plank'],
  '悬垂举腿': ['hanging leg raise'],
  '俄罗斯转体': ['russian twist'],
  '登山跑': ['mountain climber'],
  '山羊挺身': ['back extension'],
  '站姿提踵': ['standing calf raise'],
  '耸肩': ['shrug'],
  '杠铃耸肩': ['barbell shrug'],
  '飞鸟': ['fly'],
  '哑铃飞鸟': ['dumbbell fly'],
  '绳索夹胸': ['cable crossover'],
  '农夫行走': ['farmer'],
  '倒立撑': ['handstand push'],
};

const muscleZh = <String, String>{
  'abdominals': '腹肌', 'abs': '腹肌', 'adductors': '内收肌', 'biceps': '肱二头肌',
  'calves': '小腿', 'chest': '胸', 'pectorals': '胸', 'quads': '股四头肌',
  'quadriceps': '股四头肌', 'glutes': '臀', 'hamstrings': '腘绳肌',
  'lats': '背阔肌', 'lower back': '下背', 'middle back': '中背', 'upper back': '上背',
  'shoulders': '肩', 'deltoids': '三角肌', 'traps': '斜方肌', 'trapezius': '斜方肌',
  'triceps': '肱三头肌', 'forearms': '前臂', 'hip flexors': '屈髋肌',
};

const equipmentZh = <String, String>{
  'barbell': '杠铃', 'dumbbell': '哑铃', 'machine': '器械',
  'leverage machine': '器械', 'smith machine': '史密斯机', 'cable': '绳索',
  'cable machine': '绳索', 'body only': '自重', 'body weight': '自重',
  'none': '无器械', 'bands': '弹力带', 'band': '弹力带', 'kettlebells': '壶铃',
  'kettlebell': '壶铃', 'e-z curl bar': '曲杆', 'ez barbell': '曲杆',
  'olympic barbell': '奥杆', 'exercise ball': '瑞士球', 'stability ball': '瑞士球',
  'bosu ball': '波速球', 'medicine ball': '药球', 'rope': '战绳',
  'pull up bar': '单杠', 'weighted': '负重', 'wheel roller': '健腹轮',
};

const categoryZh = <String, String>{
  'waist': '腰腹', 'back': '背', 'arms': '手臂', 'chest': '胸', 'legs': '腿',
  'shoulders': '肩', 'full body': '全身', 'cardio': '有氧',
  'powerlifting': '力量举', 'strength': '力量', 'stretching': '拉伸',
  'olympic weightlifting': '举重', 'strongman': '大力士', 'plyometrics': '爆发力',
};
