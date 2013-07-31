#!/usr/bin/python3
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

import os
import re
import sh
import sys
import unittest
import tempfile

sys.path.append('./tests')
import helpers

#only for setup
sys.path.append('./dist-packages')
import tb3.repostate

class TestTb3LocalClient(unittest.TestCase):
    def setUp(self):
        (self.branch, self.platform, self.builder) = ('master', 'linux', 'testbuilder')
        os.environ['PATH'] += ':.'
        (self.testdir, self.git) = helpers.createTestRepo()
        self.logdir = tempfile.mkdtemp()
        self.tb3localclient = sh.Command.bake(sh.Command("tb3-local-client"),
            '--proposal-source', self.testdir, self.branch, self.platform, 1, 1,
            builder=self.builder,
            tb3_master='./tb3',
            script='./tests/build-script.sh',
            logdir=self.logdir,
            count=1)
        self.state = tb3.repostate.RepoState(self.platform, self.branch, self.testdir)
        self.history = tb3.repostate.RepoHistory(self.platform, self.testdir)
        self.head = self.state.get_head()
    def tearDown(self):
        sh.rm('-r', self.testdir)
    def test_runonce(self):
        self.tb3localclient()
        self.assertEqual(self.state.get_last_good(), self.head)
        state = self.history.get_commit_state(self.head)
        self.assertEqual(state.state, 'GOOD')
        self.assertEqual(state.builder, self.builder)
        logdirs = [entry for entry in os.walk(self.logdir)]
        self.assertEqual(len(logdirs), 1) # no subdirs
        self.assertEqual(logdirs[0][0], self.logdir)
        self.assertEqual(len(logdirs[0][1]), 0)
        logfiles = logdirs[0][2]
        self.assertEqual(len(logfiles), 1) # only one file in dir
        self.assertEqual(state.artifactreference, logfiles[0])
        logfile = open(os.path.join(self.logdir, logfiles[0]), 'r')
        lines = [line for line in logfile]
        self.assertEqual(len(lines), 1)
        self.assertNotEqual(re.search('building commit %s' % self.head, lines[0]), None)
        self.assertNotEqual(re.search('from repo %s' % self.testdir, lines[0]), None)
        self.assertNotEqual(re.search('on platform %s' % self.platform, lines[0]), None)
        self.assertNotEqual(re.search('as builder %s' % self.builder, lines[0]), None)

if __name__ == '__main__':
    unittest.main()
# vim: set et sw=4 ts=4:
