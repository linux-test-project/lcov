/*
 * HelloWorld.java - source for the LCOV Java/JaCoCo coverage example.
 *
 * The 'example_java' target of the Makefile in this directory copies this file
 * into 'src/hello/HelloWorld.java' of a throwaway git repo - which is where the
 * package declaration below expects it, and which gives the annotate and
 * version callbacks in the report step something to annotate against.
 *
 * There is more here than a greeting because a coverage report of a program
 * which contains only a print is not too interesting.
 * This example contains a method which isn't called, a branch that isn't
 * taken, and a loop - so it shows covered, partly covered, and uncovered code.
 */

package hello;

public class HelloWorld
{
    /** Greet somebody, or the world when nobody was named. */
    static String greet(String who)
    {
        if (who == null || who.isEmpty()) {
            return "Hello, world!";
        }
        return "Hello, " + who + "!";
    }

    /** The sum of 1..n, the slow way, so there is a loop to cover. */
    static int sum(int n)
    {
        int total = 0;
        for (int i = 1; i <= n; ++i) {
            total += i;
        }
        return total;
    }

    /** Never called by the test:  this is what uncovered code looks like. */
    static String shout(String who)
    {
        return greet(who).toUpperCase();
    }

    public static void main(String[] args)
    {
        String who = args.length > 0 ? args[0] : null;
        System.out.println(greet(who));
        System.out.println("sum(1..10) = " + sum(10));
    }
}
