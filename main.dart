import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

String keyOf(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);
DateTime only(DateTime d)=>DateTime(d.year,d.month,d.day);

class Habit {
  String id,name,emoji; List<int> days; Set<String> completions;
  Habit({required this.id,required this.name,required this.emoji,required this.days,Set<String>? completions}):completions=completions??{};
  bool scheduled(DateTime d)=>days.contains(d.weekday);
  bool done(DateTime d)=>completions.contains(keyOf(d));
  int currentStreak(){
    var d=only(DateTime.now()); int n=0;
    if(!done(d)) d=d.subtract(const Duration(days:1));
    while(true){
      while(!scheduled(d)) d=d.subtract(const Duration(days:1));
      if(!done(d)) break;
      n++; d=d.subtract(const Duration(days:1));
    }
    return n;
  }
  int longestStreak(){
    if(completions.isEmpty)return 0;
    final ds=completions.map(DateTime.parse).toList()..sort();
    int best=0,run=0; DateTime? prev;
    for(final d in ds){run=(prev!=null&&d.difference(prev!).inDays==1)?run+1:1;best=best<run?run:best;prev=d;}
    return best;
  }
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'emoji':emoji,'days':days,'completions':completions.toList()};
  factory Habit.fromJson(Map<String,dynamic> j)=>Habit(id:j['id'],name:j['name'],emoji:j['emoji']??'🎯',days:List<int>.from(j['days']??[1,2,3,4,5,6,7]),completions:Set<String>.from(j['completions']??[]));
}

class Store extends ChangeNotifier {
  final habits=<Habit>[]; SharedPreferences? p; String name=''; String? photo; ThemeMode mode=ThemeMode.system;
  Future<void> load()async{
    p=await SharedPreferences.getInstance();
    final r=p!.getString('habits'); if(r!=null)habits.addAll((jsonDecode(r) as List).map((e)=>Habit.fromJson(e)));
    name=p!.getString('name')??''; photo=p!.getString('photo');
    mode=ThemeMode.values.firstWhere((x)=>x.name==(p!.getString('theme')??'system'),orElse:()=>ThemeMode.system);notifyListeners();
  }
  Future<void> save()async{await p?.setString('habits',jsonEncode(habits.map((x)=>x.toJson()).toList()));notifyListeners();}
  Future<void> add(String n,String e,List<int>d)async{habits.add(Habit(id:DateTime.now().microsecondsSinceEpoch.toString(),name:n.trim(),emoji:e,days:d));await save();}
  Future<void> edit(Habit h,String n,String e,List<int>d)async{h.name=n.trim();h.emoji=e;h.days=d;await save();}
  Future<void> remove(Habit h)async{habits.remove(h);await save();}
  Future<void> toggle(Habit h,DateTime d)async{final k=keyOf(d);h.completions.contains(k)?h.completions.remove(k):h.completions.add(k);await save();}
  Future<void> profile(String n,String? ph)async{name=n.trim();photo=ph;await p?.setString('name',name);if(ph==null)await p?.remove('photo');else await p?.setString('photo',ph);notifyListeners();}
  Future<void> theme(ThemeMode m)async{mode=m;await p?.setString('theme',m.name);notifyListeners();}
  Map<String,dynamic> backup()=>{'version':1,'name':name,'habits':habits.map((h)=>h.toJson()).toList()};
}

void main()async{WidgetsFlutterBinding.ensureInitialized();final s=Store();await s.load();runApp(App(s));}

class App extends StatelessWidget{
 final Store s; const App(this.s,{super.key});
 @override Widget build(BuildContext c)=>AnimatedBuilder(animation:s,builder:(_,__)=>MaterialApp(
  debugShowCheckedModeBanner:false,title:'HabitFlow',themeMode:s.mode,
  theme:theme(Brightness.light),darkTheme:theme(Brightness.dark),home:Shell(s)));
}
ThemeData theme(Brightness b){final d=b==Brightness.dark;return ThemeData(
 useMaterial3:true,brightness:b,colorSchemeSeed:const Color(0xFF7656E8),
 scaffoldBackgroundColor:d?const Color(0xFF101014):const Color(0xFFF7F6FA),
 cardTheme:CardThemeData(elevation:0,color:d?const Color(0xFF1A1A20):Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18))),
 inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder(),filled:true));}

class Shell extends StatefulWidget{final Store s;const Shell(this.s,{super.key});@override State<Shell> createState()=>_Shell();}
class _Shell extends State<Shell>{int i=0;@override Widget build(BuildContext c){final p=[Today(s:widget.s),Cal(s:widget.s),Stats(s:widget.s),Profile(s:widget.s)];return Scaffold(body:SafeArea(child:p[i]),
 floatingActionButton:i==0?FloatingActionButton.extended(onPressed:()=>editor(c,widget.s),icon:const Icon(Icons.add),label:const Text('Habit')):null,
 bottomNavigationBar:NavigationBar(selectedIndex:i,onDestinationSelected:(x)=>setState(()=>i=x),destinations:const[
  NavigationDestination(icon:Icon(Icons.today_outlined),selectedIcon:Icon(Icons.today),label:'Today'),
  NavigationDestination(icon:Icon(Icons.calendar_month_outlined),selectedIcon:Icon(Icons.calendar_month),label:'Calendar'),
  NavigationDestination(icon:Icon(Icons.insights_outlined),selectedIcon:Icon(Icons.insights),label:'Stats'),
  NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Profile') ]));}}

class Today extends StatelessWidget{final Store s;const Today({super.key,required this.s});@override Widget build(BuildContext c){
 final d=only(DateTime.now()),hs=s.habits.where((h)=>h.scheduled(d)).toList(),done=hs.where((h)=>h.done(d)).length,p=hs.isEmpty?0:done/hs.length;
 final up=s.habits.where((h)=>!h.scheduled(d)).take(4);
 return ListView(padding:const EdgeInsets.fromLTRB(20,22,20,100),children:[
  Text('Good ${d.hour<12?'morning':d.hour<17?'afternoon':'evening'}, ${s.name.isEmpty?'there':s.name} 👋',style:Theme.of(c).textTheme.titleMedium),
  const SizedBox(height:4),Text('Build your future, one habit at a time.',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
  const SizedBox(height:4),Text(DateFormat('EEEE, d MMMM').format(d),style:const TextStyle(color:Colors.grey)),
  const SizedBox(height:20),Card(child:Padding(padding:const EdgeInsets.all(20),child:Row(children:[
   SizedBox(width:78,height:78,child:Stack(alignment:Alignment.center,children:[CircularProgressIndicator(value:p,strokeWidth:8),Text('$done/${hs.length}',style:const TextStyle(fontWeight:FontWeight.bold))])),
   const SizedBox(width:18),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(p==1&&hs.isNotEmpty?'Perfect day! 🎉':"Today's progress",style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    const SizedBox(height:5),Text(hs.isEmpty?'Start with one small habit.':'${(p*100).round()}% complete')]))]))),
  const SizedBox(height:22),Text("Today's habits",style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:10),
  if(hs.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(children:const[Text('🌱',style:TextStyle(fontSize:42)),SizedBox(height:8),Text('No habits scheduled today',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),SizedBox(height:5),Text('Tap “Habit” to create one.',textAlign:TextAlign.center)])))
  else ...hs.map((h)=>Tile(h,s,d)),
  if(up.isNotEmpty)...[const SizedBox(height:18),Text('Upcoming',style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),...up.map((h)=>Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(leading:CircleAvatar(child:Text(h.emoji)),title:Text(h.name),subtitle:Text('Scheduled: ${h.days.map((x)=>['','Mon','Tue','Wed','Thu','Fri','Sat','Sun'][x]).join(', ')}'))))]
 ]);}}
class Tile extends StatelessWidget{final Habit h;final Store s;final DateTime d;const Tile(this.h,this.s,this.d,{super.key});@override Widget build(BuildContext c){final ok=h.done(d);return Card(margin:const EdgeInsets.only(bottom:9),child:InkWell(borderRadius:BorderRadius.circular(18),onTap:()=>s.toggle(h,d),onLongPress:()=>editor(c,s,habit:h),child:Padding(padding:const EdgeInsets.symmetric(horizontal:15,vertical:14),child:Row(children:[
 CircleAvatar(radius:24,child:Text(h.emoji,style:const TextStyle(fontSize:22))),const SizedBox(width:13),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Text(h.name,style:TextStyle(fontSize:16,fontWeight:FontWeight.w600,decoration:ok?TextDecoration.lineThrough:null)),const SizedBox(height:4),Text('🔥 ${h.currentStreak()} day streak · 🏆 ${h.longestStreak()} best',style:const TextStyle(fontSize:12,color:Colors.grey))])),
 Icon(ok?Icons.check_circle:Icons.circle_outlined,size:32,color:ok?Theme.of(c).colorScheme.primary:Colors.grey)
 ])));}}

class Cal extends StatefulWidget{final Store s;const Cal({super.key,required this.s});@override State<Cal> createState()=>_Cal();}
class _Cal extends State<Cal>{Habit? sel;DateTime m=only(DateTime.now());@override Widget build(BuildContext c){final first=DateTime(m.year,m.month,1),count=DateTime(m.year,m.month+1,0).day,off=first.weekday-1;final list=sel==null?widget.s.habits: [sel!];return ListView(padding:const EdgeInsets.all(20),children:[
 Text('Calendar',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:4),const Text('See your consistency at a glance.',style:TextStyle(color:Colors.grey)),const SizedBox(height:16),
 DropdownButtonFormField<Habit?>(value:sel,decoration:const InputDecoration(labelText:'Habit'),items:[const DropdownMenuItem(value:null,child:Text('All habits')), ...widget.s.habits.map((h)=>DropdownMenuItem(value:h,child:Text('${h.emoji} ${h.name}')))],onChanged:(v)=>setState(()=>sel=v)),
 const SizedBox(height:12),Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(children:[
 Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[IconButton(onPressed:()=>setState(()=>m=DateTime(m.year,m.month-1,1)),icon:const Icon(Icons.chevron_left)),Text(DateFormat('MMMM yyyy').format(m),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),IconButton(onPressed:()=>setState(()=>m=DateTime(m.year,m.month+1,1)),icon:const Icon(Icons.chevron_right))]),
 Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:['M','T','W','T','F','S','S'].map((x)=>SizedBox(width:34,child:Text(x,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))).toList())),
 const SizedBox(height:8),GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,mainAxisSpacing:6,crossAxisSpacing:5),itemCount:off+count,itemBuilder:(_,i){if(i<off)return const SizedBox();final d=DateTime(m.year,m.month,i-off+1);final sh=list.where((h)=>h.scheduled(d)).toList();final complete=sh.isNotEmpty&&sh.every((h)=>h.done(d));return Container(decoration:BoxDecoration(shape:BoxShape.circle,color:complete?Theme.of(c).colorScheme.primary.withOpacity(.9):sh.isNotEmpty?Theme.of(c).colorScheme.primary.withOpacity(.10):null),alignment:Alignment.center,child:Text('${d.day}',style:TextStyle(color:complete?Colors.white:null,fontWeight:complete?FontWeight.bold:null)));})
 ]))) ]);}}

class Stats extends StatelessWidget{final Store s;const Stats({super.key,required this.s});@override Widget build(BuildContext c){final now=only(DateTime.now());int sch=0,done=0,total=0,best=0,current=0;for(final h in s.habits){total+=h.completions.length;best=best<h.longestStreak()?h.longestStreak():best;current=current<h.currentStreak()?h.currentStreak():current;for(int i=0;i<7;i++){final d=now.subtract(Duration(days:i));if(h.scheduled(d)){sch++;if(h.done(d))done++;}}}final rate=sch==0?0:(done/sch*100).round();return ListView(padding:const EdgeInsets.all(20),children:[
 Text('Statistics',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:4),const Text('Measure consistency, not perfection.',style:TextStyle(color:Colors.grey)),const SizedBox(height:18),
 Row(children:[Stat('🔥','$current','Current'),const SizedBox(width:8),Stat('🏆','$best','Best'),const SizedBox(width:8),Stat('📈','$rate%','7-day')]),const SizedBox(height:18),
 Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Last 7 days',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),const SizedBox(height:14),...List.generate(7,(i){final d=now.subtract(Duration(days:6-i));final a=s.habits.where((h)=>h.scheduled(d)).length,b=s.habits.where((h)=>h.scheduled(d)&&h.done(d)).length;return Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[SizedBox(width:38,child:Text(DateFormat('EEE').format(d))),Expanded(child:LinearProgressIndicator(value:a==0?0:b/a,minHeight:9,borderRadius:BorderRadius.circular(9))),const SizedBox(width:8),Text('$b/$a')]));})]))),
 const SizedBox(height:18),Text('Your habits',style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),...s.habits.map((h)=>Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(leading:Text(h.emoji,style:const TextStyle(fontSize:25)),title:Text(h.name),subtitle:Text('${h.completions.length} completed · ${h.longestStreak()} best'),trailing:Text('🔥 ${h.currentStreak()}'))))
 ]);}}
class Stat extends StatelessWidget{final String a,b,c;const Stat(this.a,this.b,this.c,{super.key});@override Widget build(BuildContext x)=>Expanded(child:Card(child:Padding(padding:const EdgeInsets.symmetric(vertical:15),child:Column(children:[Text(a),const SizedBox(height:4),Text(b,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text(c,style:const TextStyle(fontSize:11,color:Colors.grey))])));}

class Profile extends StatelessWidget{final Store s;const Profile({super.key,required this.s});
 Future<void> edit(BuildContext c)async{final n=TextEditingController(text:s.name);String? ph=s.photo;final pick=ImagePicker();await showModalBottomSheet(context:c,isScrollControlled:true,showDragHandle:true,builder:(x)=>StatefulBuilder(builder:(x,set)=>Padding(padding:EdgeInsets.fromLTRB(20,10,20,MediaQuery.of(x).viewInsets.bottom+25),child:Column(mainAxisSize:MainAxisSize.min,children:[
 Text('Edit profile',style:Theme.of(x).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:15),
 GestureDetector(onTap:()async{final z=await pick.pickImage(source:ImageSource.gallery,imageQuality:85);if(z!=null)set(()=>ph=z.path);},child:CircleAvatar(radius:44,backgroundImage:ph!=null?FileImage(File(ph!)):null,child:ph==null?const Icon(Icons.add_a_photo):null)),
 const SizedBox(height:14),TextField(controller:n,decoration:const InputDecoration(labelText:'Your name')),const SizedBox(height:14),
 Row(children:[Expanded(child:FilledButton(onPressed:()async{await s.profile(n.text,ph);if(x.mounted)Navigator.pop(x);},child:const Text('Save'))),if(ph!=null)IconButton(onPressed:()=>set(()=>ph=null),icon:const Icon(Icons.delete_outline))])
 ]))));}
 Future<void> csv(BuildContext c)async{final rows=<List<dynamic>>[['Date','Habit','Scheduled','Completed','Current Streak','Longest Streak']];for(final h in s.habits){for(int i=0;i<365;i++){final d=only(DateTime.now().subtract(Duration(days:i)));if(h.scheduled(d)||h.done(d))rows.add([keyOf(d),h.name,h.scheduled(d),h.done(d),h.currentStreak(),h.longestStreak()]);}}final dir=await getTemporaryDirectory(),f=File('${dir.path}/habitflow_export.csv');await f.writeAsString(const ListToCsvConverter().convert(rows));await Share.shareXFiles([XFile(f.path)],text:'HabitFlow CSV export');}
 Future<void> backup(BuildContext c)async{final dir=await getTemporaryDirectory(),f=File('${dir.path}/habitflow_backup.json');await f.writeAsString(jsonEncode(s.backup()));await Share.shareXFiles([XFile(f.path)],text:'HabitFlow backup');}
 @override Widget build(BuildContext c){final total=s.habits.fold(0,(n,h)=>n+h.completions.length),best=s.habits.fold(0,(n,h)=>n>h.longestStreak()?n:h.longestStreak());return ListView(padding:const EdgeInsets.fromLTRB(20,24,20,40),children:[
 Text('Profile',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:18),
 Card(child:Padding(padding:const EdgeInsets.all(20),child:Row(children:[CircleAvatar(radius:38,backgroundImage:s.photo!=null?FileImage(File(s.photo!)):null,child:s.photo==null?Text(s.name.isEmpty?'?':s.name[0].toUpperCase(),style:const TextStyle(fontSize:30,fontWeight:FontWeight.bold)):null),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(s.name.isEmpty?'Your name':s.name,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:4),const Text('Build your future with today’s habit.',style:TextStyle(color:Colors.grey))])),IconButton(onPressed:()=>edit(c),icon:const Icon(Icons.edit_outlined))]))),
 const SizedBox(height:10),Row(children:[Stat('🔥','${s.habits.fold(0,(n,h)=>n+h.currentStreak())}','Streaks'),const SizedBox(width:8),Stat('🏆','$best','Best'),const SizedBox(width:8),Stat('✓','$total','Completed')]),
 const SizedBox(height:20),Text('Tools',style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
 Card(child:Column(children:[
 ListTile(leading:const Icon(Icons.emoji_events_outlined),title:const Text('Achievements'),subtitle:const Text('Milestones and badges'),onTap:()=>achievements(c,s)),
 ListTile(leading:const Icon(Icons.file_download_outlined),title:const Text('Export CSV'),subtitle:const Text('Share your habit history'),onTap:()=>csv(c)),
 ListTile(leading:const Icon(Icons.backup_outlined),title:const Text('Backup data'),subtitle:const Text('Create a JSON backup'),onTap:()=>backup(c)),
 ListTile(leading:const Icon(Icons.dark_mode_outlined),title:const Text('Appearance'),subtitle:Text(s.mode==ThemeMode.system?'System default':s.mode==ThemeMode.dark?'Dark':'Light'),onTap:()=>themeDialog(c,s)),
 ListTile(leading:const Icon(Icons.info_outline),title:const Text('About HabitFlow'),subtitle:const Text('Version 1.1.0'),onTap:()=>showAboutDialog(context:c,applicationName:'HabitFlow',applicationVersion:'1.1.0',applicationLegalese:'Build your future with today’s habit.'))
 ]))
 ]);}}
void themeDialog(BuildContext c,Store s)=>showDialog(context:c,builder:(_)=>SimpleDialog(title:const Text('Appearance'),children:[for(final x in [ThemeMode.system,ThemeMode.light,ThemeMode.dark])RadioListTile(value:x,groupValue:s.mode,onChanged:(v){if(v!=null){s.theme(v);Navigator.pop(c);}},title:Text(x==ThemeMode.system?'System default':x==ThemeMode.light?'Light':'Dark'))]));
void achievements(BuildContext c,Store s){final total=s.habits.fold(0,(n,h)=>n+h.completions.length),best=s.habits.fold(0,(n,h)=>n>h.longestStreak()?n:h.longestStreak());showModalBottomSheet(context:c,showDragHandle:true,builder:(_)=>ListView(padding:const EdgeInsets.all(20),children:[Text('Achievements',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),Ach('🌱','First Habit','Create your first habit',s.habits.isNotEmpty),Ach('🔥','On Fire','7-day streak',best>=7),Ach('🔥','Unstoppable','30-day streak',best>=30),Ach('💯','Century','100 check-ins',total>=100)]));}
class Ach extends StatelessWidget{final String a,b,d;final bool ok;const Ach(this.a,this.b,this.d,this.ok,{super.key});@override Widget build(BuildContext c)=>ListTile(leading:CircleAvatar(child:Text(a)),title:Text(b,style:TextStyle(fontWeight:FontWeight.bold,color:ok?null:Colors.grey)),subtitle:Text(d),trailing:Icon(ok?Icons.check_circle:Icons.lock_outline));}

Future<void> editor(BuildContext c,Store s,{Habit? habit})async{final n=TextEditingController(text:habit?.name??'');String e=habit?.emoji??'🎯';List<int>d=List<int>.from(habit?.days??[1,2,3,4,5,6,7]);final icons=['🎯','📚','💧','🏃','🧘','💻','🛌','🥗','🧹','🎸','✍️','🧠'];await showModalBottomSheet(context:c,isScrollControlled:true,showDragHandle:true,builder:(x)=>StatefulBuilder(builder:(x,set)=>Padding(padding:EdgeInsets.fromLTRB(20,8,20,MediaQuery.of(x).viewInsets.bottom+24),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Text(habit==null?'Create habit':'Edit habit',style:Theme.of(x).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:15),TextField(controller:n,decoration:const InputDecoration(labelText:'Habit name',hintText:'e.g. Read 20 minutes')),const SizedBox(height:14),const Text('Icon',style:TextStyle(fontWeight:FontWeight.bold)),Wrap(spacing:6,children:icons.map((q)=>ChoiceChip(label:Text(q,style:const TextStyle(fontSize:19)),selected:e==q,onSelected:(_)=>set(()=>e=q))).toList()),const SizedBox(height:14),const Text('Repeat on',style:TextStyle(fontWeight:FontWeight.bold)),Wrap(spacing:6,children:List.generate(7,(i){final q=i+1;return FilterChip(label:Text(['M','T','W','T','F','S','S'][i]),selected:d.contains(q),onSelected:(v)=>set(()=>v?d.add(q):d.remove(q)));})),const SizedBox(height:20),SizedBox(width:double.infinity,child:FilledButton(onPressed:n.text.trim().isEmpty||d.isEmpty?null:()async{habit==null?await s.add(n.text,e,d):await s.edit(habit,n.text,e,d);if(x.mounted)Navigator.pop(x);},child:Text(habit==null?'Create habit':'Save changes'))),if(habit!=null)TextButton.icon(onPressed:()async{await s.remove(habit);if(x.mounted)Navigator.pop(x);},icon:const Icon(Icons.delete_outline),label:const Text('Delete habit'))
])))));}
