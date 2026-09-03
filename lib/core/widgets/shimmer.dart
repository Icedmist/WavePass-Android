import 'package:flutter/material.dart';
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, this.base = const Color(0xFFF0F0F0), this.highlight = Colors.white});
  final Widget child; final Color base; final Color highlight;
  @override State<Shimmer> createState() => _SState();
}
class _SState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState(){ super.initState(); _c=AnimationController(vsync:this,duration:const Duration(milliseconds:1400))..repeat();}
  @override void dispose(){ _c.dispose(); super.dispose();}
  @override Widget build(BuildContext context)=> AnimatedBuilder(animation:_c, builder:(c, ch)=> ShaderMask(shaderCallback:(r)=> LinearGradient(colors:[widget.base,widget.highlight,widget.base], stops: [(_c.value-0.3).clamp(0,1), _c.value.clamp(0,1), (_c.value+0.3).clamp(0,1)], begin: Alignment.centerLeft, end: Alignment.centerRight).createShader(r), blendMode: BlendMode.srcATop, child: ch), child: widget.child);
}
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({super.key, this.w, this.h, this.r=12}); final double? w,h; final double r;
  @override Widget build(BuildContext context)=> Shimmer(child: Container(width:w,height:h,decoration:BoxDecoration(color: const Color(0xFFF0F0F0),borderRadius: BorderRadius.circular(r))));
}
