# To change this license header, choose License Headers in Project Properties.
# To change this template file, choose Tools | Templates
# and open the template in the editor.

__author__ = "Joshua Schaeffer"
__date__ = "$Nov 23, 2015 3:53:23 PM$"

import os
import sys

class Automate(object):
    """A class that automates running MSSQL stored procedures."""
    def __init__(self):
        self.server = sys.argv[1]
        self.database = sys.argv[2]
        self.login = sys.argv[3]
        self.password = sys.argv[4]
        
    def description(self):
        print "I'm a %s %s and I taste %s." % (self.color, self.name, self.flavor)
    
    def is_edible(self):
        if not self.poisonous:
            print "Yep! I'm edible."
        else:
            print "Don't eat me! I am super poisonous."
            
lemon = Fruit()

if __name__ == "__main__":
    lemon.description()
    lemon.is_edible()
