import click


# Function: run
#   Example for a bottle-specific target
#
@click.pass_obj
def run(ctx):
    """Example for a bottle-specific target"""
    print("Bottle-specific target")


def pre_run():
    """Example for a bottle-specific pre-run hook"""
    print("I'm executed before run!")


def post_run():
    """Example for a bottle-specific post-run hook"""
    print("I'm executed after run!")
