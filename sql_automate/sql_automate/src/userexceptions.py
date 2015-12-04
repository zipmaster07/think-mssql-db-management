"""comment
"""

__author__  = "Joshua Schaeffer"
__date__    = "$Nov 30, 2015 12:13:43 PM$"

class Error(Exception):
    """Base class for exceptions in this module."""
    pass

class NullAttributeError(Error):
    """Exceptions for null argument values
        
        Attributes:
            error_type  -   Defines which function to call.
            username    -   The MSSQL login used to connect to the server.
            password    -   The password for the MSSQL login.
    """
    
    def __init__(self, error_type, username, password):        
        self.error_type = error_type
        self.username = username
        self.password = password
        
        if self.error_type == 'username':
            check_password()
    
    def check_password(self):
        """If the user provided a username/login but did not provide a password then return an error.
        """
        
        if self.username is not None and self.password is None:
            msg = "A username was provided but no password was given."
        return msg
            
class AttributeConflictError(Error):
    """Execptions when conflicting arguments are used together"""
    pass