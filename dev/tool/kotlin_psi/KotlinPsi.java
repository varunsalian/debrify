import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import org.jetbrains.kotlin.cli.jvm.compiler.EnvironmentConfigFiles;
import org.jetbrains.kotlin.cli.jvm.compiler.KotlinCoreEnvironment;
import org.jetbrains.kotlin.config.CompilerConfiguration;
import org.jetbrains.kotlin.com.intellij.openapi.util.Disposer;
import org.jetbrains.kotlin.com.intellij.psi.*;
import org.jetbrains.kotlin.lexer.KotlinLexer;
import org.jetbrains.kotlin.lexer.KtTokens;
import org.jetbrains.kotlin.psi.*;

/** Syntax only: the project's cached Kotlin 2.2.20 PSI and lexer, no resolver. */
public final class KotlinPsi {
    private static String source;
    private static int[] codePointOffsets;

    private static int offset(int utf16) {
        return codePointOffsets[utf16];
    }

    private static String quote(String text) {
        StringBuilder out = new StringBuilder("\"");
        for (char c : text.toCharArray()) {
            switch (c) {
                case '"': out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (c < 32) out.append(String.format("\\u%04x", (int)c));
                    else out.append(c);
            }
        }
        return out.append('"').toString();
    }

    private static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof String) return quote((String)value);
        if (value instanceof Map) {
            List<String> parts = new ArrayList<>();
            ((Map<?, ?>)value).forEach((k, v) -> parts.add(quote(k.toString()) + ":" + json(v)));
            return "{" + String.join(",", parts) + "}";
        }
        if (value instanceof Iterable) {
            List<String> parts = new ArrayList<>();
            for (Object item : (Iterable<?>)value) parts.add(json(item));
            return "[" + String.join(",", parts) + "]";
        }
        return value.toString();
    }

    private static Map<String, Object> map(Object... pairs) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) result.put((String)pairs[i], pairs[i + 1]);
        return result;
    }

    private static String types(List<KtParameter> params) {
        List<String> result = new ArrayList<>();
        for (KtParameter p : params) {
            result.add((p.isVarArg() ? "vararg " : "") +
                (p.getTypeReference() == null ? "<inferred>" : p.getTypeReference().getText()));
        }
        return String.join(",", result);
    }

    private static String selector(KtDeclaration d) {
        if (d instanceof KtObjectDeclaration) {
            KtObjectDeclaration o = (KtObjectDeclaration)d;
            return o.isCompanion() ? "companion " + (o.getName() == null ? "Companion" : o.getName()) :
                "object " + (o.getName() == null ? "<anonymous>" : o.getName());
        }
        if (d instanceof KtClass) return "class " + ((KtClass)d).getName();
        if (d instanceof KtNamedFunction) {
            KtNamedFunction f = (KtNamedFunction)d;
            String receiver = f.getReceiverTypeReference() == null ? "" : f.getReceiverTypeReference().getText() + ".";
            return "fun " + receiver + f.getName() + "(" + types(f.getValueParameters()) + ")";
        }
        if (d instanceof KtProperty) return "property " + ((KtProperty)d).getName();
        if (d instanceof KtParameter) return "constructor_property " + ((KtParameter)d).getName();
        if (d instanceof KtAnonymousInitializer) return "init";
        if (d instanceof KtSecondaryConstructor) return "constructor(" + types(((KtSecondaryConstructor)d).getValueParameters()) + ")";
        if (d instanceof KtPropertyAccessor) return ((KtPropertyAccessor)d).isGetter() ? "getter" : "setter";
        if (d instanceof KtTypeAlias) return "typealias " + ((KtTypeAlias)d).getName();
        if (d instanceof KtDestructuringDeclaration) return "destructuring " + d.getText().split("=")[0].trim();
        throw new IllegalArgumentException("Unclassified declaration " + d.getClass().getName() + " at " + offset(d.getTextOffset()));
    }

    private static boolean inventory(KtDeclaration d) {
        // Signature components are checked as part of the complete owning header.
        return !(d instanceof KtFunctionLiteral || d instanceof KtTypeParameter || d instanceof KtPrimaryConstructor ||
                 d instanceof KtDestructuringDeclarationEntry ||
                 (d instanceof KtParameter && !((KtParameter)d).hasValOrVar()));
    }

    private static void children(PsiElement element, List<KtDeclaration> output) {
        for (PsiElement child : element.getChildren()) {
            if (child instanceof KtDeclaration && inventory((KtDeclaration)child)) output.add((KtDeclaration)child);
            else children(child, output);
        }
    }

    private static List<Map<String, Object>> declarations(PsiElement parent, String path) {
        List<KtDeclaration> decls = new ArrayList<>();
        children(parent, decls);
        Map<String, Integer> totals = new HashMap<>(), seen = new HashMap<>();
        for (KtDeclaration d : decls) totals.merge(selector(d), 1, Integer::sum);
        List<Map<String, Object>> result = new ArrayList<>();
        for (KtDeclaration d : decls) {
            String key = selector(d);
            int n = seen.merge(key, 1, Integer::sum);
            if (key.equals("init") || totals.get(key) > 1) key += "#" + n;
            String id = path.isEmpty() ? key : path + "/" + key;
            Map<String, Object> node = map("id", id, "selector", key, "kind", d.getClass().getSimpleName(),
                "start", offset(d.getTextRange().getStartOffset()), "end", offset(d.getTextRange().getEndOffset()));
            if (d instanceof KtClassOrObject) {
                KtClassBody body = ((KtClassOrObject)d).getBody();
                if (body != null) {
                    node.put("body_start", offset(body.getTextRange().getStartOffset()));
                    node.put("body_end", offset(body.getTextRange().getEndOffset()));
                    List<String> members = new ArrayList<>();
                    // IDs for the body members are resolved from their exact offsets.
                    for (KtDeclaration member : ((KtClassOrObject)d).getDeclarations()) members.add(String.valueOf(offset(member.getTextRange().getStartOffset())));
                    node.put("body_member_starts", members);
                }
            }
            node.put("children", declarations(d, id));
            result.add(node);
        }
        return result;
    }

    private static List<Map<String, Object>> tokens() {
        KotlinLexer lexer = new KotlinLexer();
        lexer.start(source);
        List<Map<String, Object>> result = new ArrayList<>();
        while (lexer.getTokenType() != null) {
            int start = lexer.getTokenStart(), end = lexer.getTokenEnd();
            String text = source.substring(start, end);
            if (lexer.getTokenType() == KtTokens.WHITE_SPACE) {
                for (int i = start; i < end; i++) {
                    if (source.charAt(i) == '\n') result.add(map("kind", "NL", "text", "\n", "start", offset(i), "end", offset(i + 1)));
                }
            } else {
                result.add(map("kind", lexer.getTokenType().toString(), "text", text, "start", offset(start), "end", offset(end)));
            }
            lexer.advance();
        }
        return result;
    }

    public static void main(String[] args) throws Exception {
        var disposable = Disposer.newDisposable();
        try {
            var environment = KotlinCoreEnvironment.createForProduction(disposable, new CompilerConfiguration(), EnvironmentConfigFiles.JVM_CONFIG_FILES);
            var factory = new KtPsiFactory(environment.getProject(), false);
            List<Object> files = new ArrayList<>();
            boolean lexerOnly = args.length > 0 && args[0].equals("--lexer-only");
            for (String arg : args) {
                if (arg.equals("--lexer-only")) continue;
                source = Files.readString(Path.of(arg), StandardCharsets.UTF_8);
                codePointOffsets = new int[source.length() + 1];
                for (int i = 0, points = 0; i < source.length(); i++) {
                    codePointOffsets[i] = points;
                    if (!Character.isLowSurrogate(source.charAt(i))) points++;
                    codePointOffsets[i + 1] = points;
                }
                if (lexerOnly) {
                    files.add(map("tokens", tokens(), "prefix_end", 0, "length", source.codePointCount(0, source.length())));
                    continue;
                }
                KtFile file = factory.createFile(Path.of(arg).getFileName().toString(), source);
                Collection<PsiErrorElement> errors = org.jetbrains.kotlin.com.intellij.psi.util.PsiTreeUtil.findChildrenOfType(file, PsiErrorElement.class);
                if (!errors.isEmpty()) throw new IllegalArgumentException("PSI syntax error: " + errors.iterator().next().getErrorDescription());
                int prefix = file.getPackageDirective() == null ? 0 : file.getPackageDirective().getTextRange().getEndOffset();
                if (file.getImportList() != null) prefix = Math.max(prefix, file.getImportList().getTextRange().getEndOffset());
                files.add(map("declarations", declarations(file, ""), "tokens", tokens(), "prefix_end", offset(prefix), "length", source.codePointCount(0, source.length())));
            }
            System.out.println(json(files));
        } finally {
            Disposer.dispose(disposable);
        }
    }
}
