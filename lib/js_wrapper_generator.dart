library js_wrapper_generator;

import 'package:analyzer_experimental/src/generated/ast.dart';
import 'package:analyzer_experimental/src/generated/error.dart';
import 'package:analyzer_experimental/src/generated/parser.dart';
import 'package:analyzer_experimental/src/generated/scanner.dart';

final wrapper = const _Wrapper();
class _Wrapper{
  const _Wrapper();
}

String transform(String code) {
  final unit = _parseCompilationUnit(code);
  final transformations = _buildTransformations(unit, code);
  return _applyTransformations(code, transformations);
}

List<_Transformation> _buildTransformations(CompilationUnit unit, String code) {
  final result = new List<_Transformation>();
  for (var declaration in unit.declarations) {
    if (declaration is ClassDeclaration && hasWrapper(declaration)) {
      // remove @wrapper
      declaration.metadata.where((m) => m.name.name == 'wrapper' && m.constructorName == null && m.arguments == null).forEach((m){
        result.add(new _Transformation(m.offset, m.endToken.next.offset, ''));
      });

      // add cast and constructor
      final name = declaration.name;
      final position = declaration.leftBracket.offset;
      final alreadyExtends = declaration.extendsClause != null;
      result.add(new _Transformation(position, position + 1,
          (alreadyExtends ? '' : 'extends jsw.TypedProxy ') + '''{
  static $name cast(js.Proxy proxy) => proxy == null ? null : new $name.fromProxy(proxy);
  $name.fromProxy(js.Proxy proxy) : super.fromProxy(proxy);'''));

      // generate member
      declaration.members.forEach((m){
        if (m is FieldDeclaration) {

        } else if (m is MethodDeclaration && m.isAbstract()) {
          bool useBracket = false;
          var wrap = (String s) => s;
          if (m.returnType != null) {
            final returnName = m.returnType.name.name;
            if (returnName == 'void') {
              useBracket = true;
            } else if (returnName == 'int' ||
                returnName == 'double' ||
                returnName == 'String' ||
                returnName == 'bool') {
            } else if (returnName == 'List') {
              if (m.returnType.typeArguments == null) {
                wrap = (String s) => 'jsw.JsArrayToListAdapter.cast($s)';
              } else {
                wrap = (String s) => 'jsw.JsArrayToListAdapter.castListOfSerializables($s, ${m.returnType.typeArguments.arguments.first}.cast)';
              }
            } else {
              wrap = (String s) => '${m.returnType}.cast($s)';
            }
          }
          final method = new StringBuffer();
          if (m.returnType != null) method..write(m.returnType)..write(' ');
          method..write(m.name)..write(m.parameters);
          if (useBracket) method.write(' { ');
          else method.write(' => ');
          method.write(wrap(r'$unsafe.' + m.name.name + '(' + m.parameters.elements.map((p) => p.name).join(', ') + ')'));
          method.write(';');
          if (useBracket) method.write(' }');
          result.add(new _Transformation(m.offset, m.end, method.toString()));
        }
      });
    }
  }
  return result;
}

/// True if the node has the `@wrapper` annotation.
bool hasWrapper(AnnotatedNode node) => hasAnnotation(node, 'wrapper');

bool hasAnnotation(AnnotatedNode node, String name) {
  return node.metadata.any((m) => m.name.name == name &&
      m.constructorName == null && m.arguments == null);
}

String _applyTransformations(String code, List<_Transformation> transformations) {
  int padding = 0;
  for (final t in transformations) {
    code = code.substring(0, t.begin + padding) + t.replace + code.substring(t.end + padding);
    padding += t.replace.length - (t.end - t.begin);
  }
  return code;
}

CompilationUnit _parseCompilationUnit(String code) {
  var errorListener = new _ErrorCollector();
  var scanner = new StringScanner(null, code, errorListener);
  var token = scanner.tokenize();
  var parser = new Parser(null, errorListener);
  var unit = parser.parseCompilationUnit(token);
  return unit;
}

class _ErrorCollector extends AnalysisErrorListener {
  final errors = new List<AnalysisError>();
  onError(error) => errors.add(error);
}

class _Transformation {
  final int begin;
  final int end;
  final String replace;
  _Transformation(this.begin, this.end, this.replace);
}