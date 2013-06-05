#! /usr/bin/env python
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

import datetime
import sh
import sys
import unittest

sys.path.append('./dist-packages')
sys.path.append('./tests')
import helpers
import tb3.repostate


class TestRepoState(unittest.TestCase):
    def __resolve_ref(self, refname):
        return self.git('show-ref', refname).split(' ')[0]
    def setUp(self):
        (self.testdir, self.git) = helpers.createTestRepo()
        self.state = tb3.repostate.RepoState('linux', 'master', self.testdir)
        self.head = self.state.get_head()
        self.preb1 = self.__resolve_ref('refs/tags/pre-branchoff-1')
        self.preb2 = self.__resolve_ref('refs/tags/pre-branchoff-2')
        self.bp = self.__resolve_ref('refs/tags/branchpoint')
        self.postb1 = self.__resolve_ref('refs/tags/post-branchoff-1')
        self.postb2 = self.__resolve_ref('refs/tags/post-branchoff-2')
    def tearDown(self):
        sh.rm('-r', self.testdir)
    def test_sync(self):
        self.state.sync()
    def test_last_good(self):
        self.state.set_last_good(self.head)
        self.assertEqual(self.state.get_last_good(), self.head)
    def test_first_bad(self):
        self.state.set_first_bad(self.head)
        self.assertEqual(self.state.get_first_bad(), self.head)
    def test_last_bad(self):
        self.state.set_last_bad(self.head)
        self.assertEqual(self.state.get_last_bad(), self.head)
    def test_last_build(self):
        self.state.set_last_good(self.preb1)
        self.assertEqual(self.state.get_last_build(), self.preb1)
        self.state.set_last_bad(self.preb2)
        self.assertEqual(self.state.get_last_build(), self.preb2)

class TestRepoHistory(unittest.TestCase):
    def setUp(self):
        (self.testdir, self.git) = helpers.createTestRepo()
        self.state = tb3.repostate.RepoState('linux', 'master', self.testdir)
        self.head = self.state.get_head()
        self.history = tb3.repostate.RepoHistory('linux', self.testdir)
    def tearDown(self):
        sh.rm('-r', self.testdir)
    def test_commitState(self):
        self.assertEqual(self.history.get_commit_state(self.head), tb3.repostate.CommitState())
        for state in tb3.repostate.CommitState.STATES:
            commitstate = tb3.repostate.CommitState(state)
            self.history.set_commit_state(self.head, commitstate)
            self.assertEqual(self.history.get_commit_state(self.head), commitstate)
        with self.assertRaises(AttributeError):
            self.history.set_commit_state(self.head, tb3.repostate.CommitState('foo!'))
 
class TestRepoUpdater(unittest.TestCase):
    def __resolve_ref(self, refname):
        return self.git('show-ref', refname).split(' ')[0]
    def setUp(self):
        (self.testdir, self.git) = helpers.createTestRepo()
        self.state = tb3.repostate.RepoState('linux', 'master', self.testdir)
        self.preb1 = self.__resolve_ref('refs/tags/pre-branchoff-1')
        self.bp = self.__resolve_ref('refs/tags/branchpoint')
        self.postb1 = self.__resolve_ref('refs/tags/post-branchoff-1')
        self.head = self.state.get_head()
        self.history = tb3.repostate.RepoHistory('linux', self.testdir)
        self.updater = tb3.repostate.RepoStateUpdater('linux', 'master', self.testdir)
    def tearDown(self):
        sh.rm('-r', self.testdir)
    def test_set_scheduled(self):
        self.updater.set_scheduled(self.head, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.head, 'testbuilder', datetime.timedelta(minutes=2400))
    def test_good_head(self):
        self.updater.set_finished(self.head, 'testbuilder', 'GOOD', 'foo')
    def test_bad_head(self):
        self.updater.set_finished(self.head, 'testbuilder', 'BAD', 'foo')
    def test_bisect(self):
        self.updater.set_scheduled(self.preb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.bp, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.postb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.head, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_finished(self.preb1, 'testbuilder', 'GOOD', 'foo')
        self.updater.set_finished(self.bp, 'testbuilder', 'GOOD', 'foo')
        self.updater.set_finished(self.postb1, 'testbuilder', 'BAD', 'foo')
        self.updater.set_finished(self.head, 'testbuilder', 'GOOD', 'foo')
        self.assertEqual(self.history.get_commit_state('%s^' % self.head).state, 'POSSIBLY_FIXING')
        self.assertEqual(self.history.get_commit_state('%s^' % self.postb1).state, 'POSSIBLY_BREAKING')
        #for (commit, state) in self.history.get_recent_commit_states('master',9):
        #    print('bisect: %s %s' % (commit, state))
        #print(self.state)
    def test_breaking(self):
        self.updater.set_scheduled(self.preb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled('%s^^' % self.postb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled('%s^' % self.postb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.head, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_finished(self.preb1, 'testbuilder', 'GOOD', 'foo')
        self.updater.set_finished('%s^^' % self.postb1, 'testbuilder', 'GOOD', 'foo')
        self.updater.set_finished('%s^' % self.postb1, 'testbuilder', 'BAD', 'foo')
        self.updater.set_finished(self.head, 'testbuilder', 'GOOD', 'foo')
        self.assertEqual(self.history.get_commit_state('%s^' % self.head).state, 'POSSIBLY_FIXING')
        self.assertEqual(self.history.get_commit_state('%s^' % self.postb1).state, 'BREAKING')
        self.assertEqual(self.history.get_commit_state('%s^^' % self.postb1).state, 'GOOD')
    def test_possibly_breaking(self):
        self.updater.set_scheduled(self.preb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.head, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_finished(self.preb1, 'testbuilder', 'GOOD', 'foo')
        self.updater.set_finished(self.head, 'testbuilder', 'BAD', 'foo')
        self.assertEqual(self.history.get_commit_state('%s^' % self.head).state, 'POSSIBLY_BREAKING')
    def test_possibly_fixing(self):
        self.updater.set_scheduled(self.preb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.bp, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.head, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_finished(self.preb1, 'testbuilder', 'GOOD', 'foo')
        self.updater.set_finished(self.bp, 'testbuilder', 'BAD', 'foo')
        self.updater.set_finished(self.head, 'testbuilder', 'GOOD', 'foo')
        self.assertEqual(self.history.get_commit_state('%s^' % self.head).state, 'POSSIBLY_FIXING')
    def test_assume_good(self):
        self.updater.set_scheduled(self.preb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.head, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_finished(self.preb1, 'testbuilder', 'GOOD', 'foo')
        self.updater.set_finished(self.head, 'testbuilder', 'GOOD', 'foo')
        self.assertEqual(self.history.get_commit_state('%s^' % self.head).state, 'ASSUMED_GOOD')
    def test_assume_bad(self):
        self.updater.set_scheduled(self.preb1, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.bp, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_scheduled(self.head, 'testbuilder', datetime.timedelta(minutes=240))
        self.updater.set_finished(self.preb1, 'testbuilder', 'GOOD', 'foo')
        self.updater.set_finished(self.bp, 'testbuilder', 'BAD', 'foo')
        self.updater.set_finished(self.head, 'testbuilder', 'BAD', 'foo')
        self.assertEqual(self.history.get_commit_state('%s^' % self.head).state, 'ASSUMED_BAD')

if __name__ == '__main__':
    unittest.main()
# vim: set et sw=4 ts=4:
